require 'rack'
require 'open-uri'
require_relative '../test_case'

RACK_CONFIG = File.join([settings.root, "config.ru"])

class TestRackAttack < TestCase

  def self.before_suite
    # Store app settings
    @@auth_setting = LinkedData.settings.enable_security
    @@throttling_setting = LinkedData.settings.enable_throttling
    @@req_per_sec_limit = LinkedData::OntologiesAPI.settings.req_per_second_per_ip
    @@safe_ips = LinkedData::OntologiesAPI.settings.safe_ips

    LinkedData.settings.enable_security = true
    LinkedData::OntologiesAPI.settings.enable_throttling = true
    LinkedData::OntologiesAPI.settings.req_per_second_per_ip = 1
    LinkedData::OntologiesAPI.settings.safe_ips = Set.new(["1.2.3.4", "1.2.3.5"])

    @@user = LinkedData::Models::User.new({username: "user", password: "test_password", email: "test_email1@example.org"})
    @@user.save

    @@bp_user = LinkedData::Models::User.new({username: "ncbobioportal", password: "test_password", email: "test_email2@example.org"})
    @@bp_user.save

    admin_role = LinkedData::Models::Users::Role.find("ADMINISTRATOR").first
    @@admin = LinkedData::Models::User.new({username: "admin", password: "test_password", email: "test_email3@example.org", role: [admin_role]})
    @@admin.save

    # Redirect output or we get a bunch of noise from Rack (gets reset in the after_suite method).
    # Disable output redirect when debugging

    $stdout = File.open("/dev/null", "w")
    $stderr = File.open("/dev/null", "w")


    @@port1 = self.new('').unused_port

    # Fork the process to create two servers. This isolates the Rack::Attack configuration, which makes other tests fail if included.
    @@pid1 = fork do
      require_relative '../../config/rack_attack'
      Rack::Server.start(
        config: RACK_CONFIG,
        Port: @@port1
      )
      Signal.trap("HUP") { Process.exit! }
    end

    @@port2 =  self.new('').unused_port
    @@pid2 = fork do
      require_relative '../../config/rack_attack'
      Rack::Server.start(
        config: RACK_CONFIG,
        Port: @@port2
      )
      Signal.trap("HUP") { Process.exit! }
    end

    # Give the servers time to start.
    sleep(5)
  end

  def self.after_suite
    # Restore app settings
    LinkedData.settings.enable_security = @@auth_setting
    LinkedData::OntologiesAPI.settings.enable_throttling = @@throttling_setting
    LinkedData::OntologiesAPI.settings.req_per_second_per_ip = @@req_per_sec_limit
    LinkedData::OntologiesAPI.settings.safe_ips = @@safe_ips

    Process.kill("TERM", @@pid1)
    Process.wait(@@pid1)
    Process.kill("TERM", @@pid2)
    Process.wait(@@pid2)

    $stdout = STDOUT
    $stderr = STDERR

    @@admin.delete
    @@user.delete
    @@bp_user.delete
  end

  def test_throttling_limit
    request_in_threads do
      assert_raises(OpenURI::HTTPError) { request }
    end
  end

  # TODO: Upgrading rack-attack from 5 to 6 causes this test to fail with a 500 Internal Server error.
  #   Project is currently pinned at 5.4.2. Investigate failure at the time we decide to upgrade.
  def test_throttling_limit_with_forwarding
    limit = LinkedData::OntologiesAPI.settings.req_per_second_per_ip 
    headers = {"Authorization" => "apikey token=#{@@user.apikey}", "X-Forwarded-For" => "1.2.3.6"}

    exception = assert_raises(OpenURI::HTTPError) do
      (limit * 5).times do
        URI.open("http://127.0.0.1:#{@@port1}/ontologies", headers)
      end
    end
    assert_match /429 Too Many Requests/, exception.message
  end

  def test_throttling_admin_override
    request_in_threads do
      assert_raises(OpenURI::HTTPError) { request }

      request(user: @@admin) do |r|
        assert r.status[0].to_i == 200
      end
    end
  end

  def test_two_servers_one_ip
    request_in_threads do
      assert_raises(OpenURI::HTTPError) { request }
      assert_raises(OpenURI::HTTPError) { request(port: @@port2) }
    end
  end

  def test_throttling_ui_override
    request_in_threads do
      assert_raises(OpenURI::HTTPError) { request }

      request(user: @@bp_user) do |r|
        assert r.status[0].to_i == 200
      end
    end
  end

  def test_throttling_safe_ips_override
    limit = LinkedData::OntologiesAPI.settings.req_per_second_per_ip
    safe_ips = LinkedData::OntologiesAPI.settings.safe_ips

    safe_ips.each do |safe_ip|
      headers = {"Authorization" => "apikey token=#{@@user.apikey}", "X-Forwarded-For" => "#{safe_ip}"}
      (limit * 5).times do
        response = URI.open("http://127.0.0.1:#{@@port1}/ontologies", headers)
        refute_match /429/, response.status.first, "Requests from a safelisted IP address were throttled"
      end
    end
  end

  private

  def request(user: nil, port: nil)
    user ||= @@user
    port ||= @@port1
    headers = {"Authorization" => "apikey token=#{user.apikey}"}
    # Make sure to do the request at least twice as many times as the limit
    # in order to more effectively reach the throttling limit.
    # Sometimes a single request can get through without failing depending
    # on the order of the request as it coincides with the threaded requests.
    (LinkedData::OntologiesAPI.settings.req_per_second_per_ip * 2).times do
      URI.open("http://127.0.0.1:#{port}/ontologies", headers)
    end
  end

  def request_in_threads(&block)
    thread_count = LinkedData::OntologiesAPI.settings.req_per_second_per_ip * 5
    threads = []
    begin
      thread_count.times do
        threads << Thread.new do
          while true
            sleep(0.2)
            request rescue next
          end
        end
      end

      sleep(0.4)

      yield
    ensure
      sleep(1)
      threads.each {|t| t.kill; t.join}
    end
  end
end
