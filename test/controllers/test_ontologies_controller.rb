require 'webrick'
require_relative '../test_case'

class TestOntologiesController < TestCase
  def self.before_suite
    _set_vars
    _delete
    _create_user
    _create_onts
  end

  def teardown
    self.class._delete_onts
    self.class._create_onts
  end

  def self._set_vars
    @@acronym = "TST"
    @@name = "Test Ontology"
    @@file_params = {
      name: @@name,
      hasOntologyLanguage: "OWL",
      administeredBy: ["tim"]
    }

    @@view_acronym = 'TST_VIEW'
    @@view_name = 'Test View of Test Ontology'
    @@view_file_params = {
        name: @@view_name,
        hasOntologyLanguage: "OWL",
        administeredBy: ["tom"]
    }
    @@server_thread = nil
    @@server_url = nil
  end

  def self._create_user
    username = "tim"
    test_user = User.new(username: username, email: "#{username}@example.org", password: "password")
    test_user.save if test_user.valid?
    @@user = test_user.valid? ? test_user : User.find(username).first
  end

  def self._delete
    _delete_onts
    test_user = User.find("tim").first
    test_user.delete unless test_user.nil?
  end

  def self._create_onts
    ont = Ontology.new(acronym: @@acronym, name: @@name, administeredBy: [@@user])
    ont.save if ont.valid?

    view = Ontology.new(acronym: @@view_acronym, name: @@view_name, administeredBy: [@@user], viewOf: ont)
    view.save
  end

  def self._delete_onts
    ont = Ontology.find(@@acronym).first
    ont.delete unless ont.nil?
    view = Ontology.find(@@view_acronym).first
    view.delete unless view.nil?
  end

  def test_all_ontologies
    num_onts_created, created_ont_acronyms = create_ontologies_and_submissions()

    get '/ontologies'
    assert last_response.ok?

    onts = MultiJson.load(last_response.body)
    assert onts.length >= num_onts_created

    all_ont_acronyms = []
    onts.each do |ont|
      all_ont_acronyms << ont["acronym"]
    end

    created_ont_acronyms.each do |acronym|
      assert all_ont_acronyms.include?(acronym)
    end
  end

  def test_single_ontology
    num_onts_created, created_ont_acronyms = create_ontologies_and_submissions(ont_count: 1)
    ontology = created_ont_acronyms.first
    get "/ontologies/#{ontology}"
    assert last_response.ok?

    ont = MultiJson.load(last_response.body)
    assert ont["acronym"] = ontology
  end

  def test_create_ontology
    self.class._delete_onts
    put "/ontologies/#{@@acronym}", @@file_params
    assert last_response.status == 201

    delete "/ontologies/#{@@acronym}"
    post "/ontologies/", @@file_params.merge(acronym: @@acronym)
    assert last_response.status == 201
  end

  def test_create_new_ontology_same_acronym
    put "/ontologies/#{@@acronym}", :name => @@name
    assert last_response.status == 409
  end

  def test_create_new_ontology_same_name
    put "/ontologies/XXX", :name => @@name
    assert last_response.status == 409
  end

  def test_create_new_ontology_acronym_invalid
    # acronym rules:
    #   - 0-9, a-z, A-Z, dash, and underscore (no spaces)
    #   - acronym must start with a letter (upper or lower case)
    #   - acronym length <= 16 characters
    #   - acronym and name must be unique
    #
    # Must begin with A-Z
    ont_name = 'Invalid Ontology Acronym'
    put "/ontologies/*abc123", :name => ont_name
    check400 last_response
    put "/ontologies/_abc123", :name => ont_name
    check400 last_response
    put "/ontologies/-abc123", :name => ont_name
    check400 last_response
    put "/ontologies/123abc", :name => ont_name
    check400 last_response
    # Must be all upper case.
    put "/ontologies/abc", :name => ont_name
    check400 last_response
    # test acronym is too long (17 > 16), otherwise this one is OK
    put "/ontologies/A1234567890123456", :name => ont_name
    check400 last_response
    # test acronym with any invalid character
    put "/ontologies/A*", :name => ont_name
    check400 last_response
  end

  def test_create_new_ontology_invalid
    put "/ontologies/NO_PROPERTIES"
    assert last_response.status == 422
    assert MultiJson.load(last_response.body)["errors"]
  end

  def test_patch_ontology
    name = "Test new name"
    new_name = {name: name}
    patch "/ontologies/#{@@acronym}", MultiJson.dump(new_name), "CONTENT_TYPE" => "application/json"
    assert last_response.status == 204

    get "/ontologies/#{@@acronym}"
    ont = MultiJson.load(last_response.body)
    assert ont["name"].eql?(name)
  end

  def test_delete_ontology
    delete "/ontologies/#{@@acronym}"
    assert last_response.status == 204

    get "/ontologies/#{@@acronym}"
    assert last_response.status == 404
  end

  def test_download_ontology
    num_onts_created, created_ont_acronyms, onts = create_ontologies_and_submissions(ont_count: 1, submission_count: 1, process_submission: true)
    assert_equal(1, num_onts_created, msg="Failed to create 1 ontology?")
    assert_equal(1, onts.length, msg="Failed to create 1 ontology?")
    ont = onts.first
    assert_instance_of(Ontology, ont, msg="ont is not a #{Ontology.class}")
    # Clear restrictions on downloads
    LinkedData::OntologiesAPI.settings.restrict_download = []
    # Download the latest submission (the generic ontology download)
    acronym = created_ont_acronyms.first
    get "/ontologies/#{acronym}/download"
    assert_equal(200, last_response.status, msg='failed download for ontology : ' + get_errors(last_response))
    # Add restriction on download
    LinkedData::OntologiesAPI.settings.restrict_download = [acronym]
    # Try download
    get "/ontologies/#{acronym}/download"
    # download should fail with a 403 status
    assert_equal(403, last_response.status, msg='failed to restrict download for ontology : ' + get_errors(last_response))
    # Clear restrictions on downloads
    LinkedData::OntologiesAPI.settings.restrict_download = []
    # see also test_ontologies_submissions_controller::test_download_submission
  end

  def test_download_ontology_csv
    num_onts_created, created_ont_acronyms, onts = create_ontologies_and_submissions(ont_count: 1, submission_count: 1,
                                                                                     process_submission: true,
                                                                                     process_options:{process_rdf: true, extract_metadata: true, index_search: true})
    ont = onts.first
    acronym = created_ont_acronyms.first

    get "/ontologies/#{acronym}/download?download_format=csv"
    assert_equal(200, last_response.status, msg="Download failure for '#{acronym}' ontology: " + get_errors(last_response))

    # Download should fail with a 400 status.
    get "/ontologies/#{acronym}/download?download_format=csr"
    assert_equal(400, last_response.status, msg="Download failure for '#{acronym}' ontology: " + get_errors(last_response))
  end

  def test_download_ontology_rdf
    created_ont_acronyms = create_ontologies_and_submissions(ont_count: 1, submission_count: 1, process_submission: true)[1]
    acronym = created_ont_acronyms.first

    get "/ontologies/#{acronym}/download?download_format=rdf"
    assert_equal(200, last_response.status, msg="Download failure for '#{acronym}' ontology: " + get_errors(last_response))

    # Download should fail with a 400 status.
    get "/ontologies/#{acronym}/download?download_format=csr"
    assert_equal(400, last_response.status, msg="Download failure for '#{acronym}' ontology: " + get_errors(last_response))
  end

  def test_download_acl_only
    ont = create_ontologies_and_submissions(ont_count: 1, submission_count: 1, process_submission: true)[2].first
    ont.bring_remaining
    acronym = ont.acronym

    begin
      allowed_user = User.new({
        username: "allowed",
        email: "test1@example.org",
        password: "12345"
      })
      allowed_user.save
      blocked_user = User.new({
        username: "blocked",
        email: "test2@example.org",
        password: "12345"
      })
      blocked_user.save

      ont.acl = [allowed_user]
      ont.viewingRestriction = "private"
      ont.save

      LinkedData.settings.enable_security = true

      get "/ontologies/#{acronym}/download?apikey=#{allowed_user.apikey}"
      assert_equal(200, last_response.status, msg="User who is in ACL couldn't download ontology")

      get "/ontologies/#{acronym}/download?apikey=#{blocked_user.apikey}"
      assert_equal(403, last_response.status, msg="User who isn't in ACL could download ontology")

      admin = ont.administeredBy.first
      admin.bring(:apikey)
      get "/ontologies/#{acronym}/download?apikey=#{admin.apikey}"
      assert_equal(200, last_response.status, msg="Admin couldn't download ontology")
    ensure
      LinkedData.settings.enable_security = false
      del = User.find("allowed").first
      del.delete if del
      del = User.find("blocked").first
      del.delete if del
    end
  end

  def test_on_demand_ontology_pull
    ont = create_ontologies_and_submissions(ont_count: 1, submission_count: 1, process_submission: true)[2].first
    ont.bring_remaining
    acronym = ont.acronym
    sub = ont.submissions.first
    sub.bring(:pullLocation) if sub.bring?(:pullLocation)
    assert_equal(nil, sub.pullLocation, msg="Pull location should be nil at this point in the test")

    allowed_user = ont.administeredBy.first
    allowed_user.bring(:apikey) if allowed_user.bring?(:apikey)

    post "/ontologies/#{acronym}/pull?apikey=#{allowed_user.apikey}"
    assert_equal(404, last_response.status, msg="This ontology is NOT configured to be remotely pulled at this point in the test. It should return status 404")

    begin
      start_server
      sub.pullLocation = RDF::IRI.new(@@server_url)
      sub.save
      LinkedData.settings.enable_security = true
      post "/ontologies/#{acronym}/pull?apikey=#{allowed_user.apikey}"
      assert_equal(204, last_response.status, msg="The ontology admin was unable to execute the on-demand pull")

      blocked_user = User.new({
        username: "blocked",
        email: "test@example.org",
        password: "12345"
      })
      blocked_user.save
      post "/ontologies/#{acronym}/pull?apikey=#{blocked_user.apikey}"
      assert_equal(403, last_response.status, msg="An unauthorized user was able to execute the on-demand pull")
    ensure
      del = User.find("blocked").first
      del.delete if del
      stop_server
      LinkedData.settings.enable_security = false
      del = User.find("blocked").first
      del.delete if del
    end
  end

  def test_detach_a_view
    view = Ontology.find(@@view_acronym).include(:viewOf).first
    ont =  view.viewOf
    refute_nil view
    refute_nil ont

    remove_view_of = {viewOf: ''}
    patch "/ontologies/#{@@view_acronym}", MultiJson.dump(remove_view_of), "CONTENT_TYPE" => "application/json"

    assert last_response.status == 204

    get "/ontologies/#{@@view_acronym}"
    onto = MultiJson.load(last_response.body)
    assert_nil onto["viewOf"]


    add_view_of = {viewOf: @@acronym}
    patch "/ontologies/#{@@view_acronym}", MultiJson.dump(add_view_of), "CONTENT_TYPE" => "application/json"

    assert last_response.status == 204

    get "/ontologies/#{@@view_acronym}?include=all"
    onto = MultiJson.load(last_response.body)
    assert_equal onto["viewOf"], ont.id.to_s
  end

  private

  def start_server
    ont_path = File.expand_path("../../data/ontology_files/BRO_v3.2.owl", __FILE__)
    file = File.new(ont_path)
    port = Random.rand(55000..65535) # http://en.wikipedia.org/wiki/List_of_TCP_and_UDP_port_numbers#Dynamic.2C_private_or_ephemeral_ports
    @@server_url = "http://localhost:#{port}/"
    @@server_thread = Thread.new do
      server = WEBrick::HTTPServer.new(Port: port)
      server.mount_proc '/' do |req, res|
        contents = file.read
        file.rewind
        res.body = contents
      end
      begin
        server.start
      ensure
        server.shutdown
      end
    end
  end

  def stop_server
    Thread.kill(@@server_thread) if @@server_thread
  end

  def check400(response)
    assert response.status >= 400
    assert MultiJson.load(response.body)["errors"]
  end

end
