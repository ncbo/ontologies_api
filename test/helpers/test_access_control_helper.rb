require_relative '../test_case_helpers'

class TestAccessControlHelper < TestCaseHelpers
  # Class instance vars with readers/writers
  class << self
    attr_accessor :usernames, :admin, :user1, :user2, :user3, :user,
                  :restricted_ont, :ont, :ont_patch, :restricted_user,
                  :old_security_setting
  end

  def before_suite
    self.backend_4s_delete

    self.class.usernames = %w[user1 user2 user3 admin]
    self.class.usernames.each do |username|
      user = LinkedData::Models::User.new(
        username: username,
        email: "#{username}@example.org",
        password: "note_user_pass"
      )
      user.save
      user.bring_remaining
      # create @user1, @user2, @user3, @admin on the class object
      self.class.send(:"#{username}=", user)
    end

    self.class.admin.role = [
      LinkedData::Models::Users::Role.find(LinkedData::Models::Users::Role::ADMIN).first
    ]
    self.class.admin.save

    onts = LinkedData::SampleData::Ontology.create_ontologies_and_submissions[2]

    self.class.restricted_ont = onts.shift
    self.class.restricted_ont.bring_remaining
    self.class.restricted_ont.viewingRestriction = "private"
    self.class.restricted_ont.acl = [self.class.user2, self.class.user3]
    self.class.restricted_ont.administeredBy = [self.class.user1]
    self.class.restricted_ont.save
    self.class.restricted_user = self.class.restricted_ont.administeredBy.first
    self.class.restricted_user.bring_remaining

    self.class.ont = onts.shift
    self.class.ont.bring_remaining
    self.class.user = self.class.ont.administeredBy.first
    self.class.user.bring_remaining

    self.class.old_security_setting = LinkedData.settings.enable_security
    self.class.ont_patch = onts.shift.bring_remaining

    LinkedData.settings.enable_security = true
  end

  def after_suite
    self.backend_4s_delete
    LinkedData.settings.enable_security = self.class.old_security_setting unless self.class.old_security_setting.nil?
  end

  def test_filtered_list
    get "/ontologies", apikey: self.class.user.apikey
    onts = MultiJson.load(last_response.body)
    assert last_response.ok?
    assert_equal 4, onts.length

    ids = onts.map { |o| o["@id"] }
    assert_includes ids, self.class.ont.id.to_s
    refute_includes ids, self.class.restricted_ont.id.to_s
  end

  def test_direct_access
    get "/ontologies/#{self.class.restricted_ont.acronym}", apikey: self.class.user.apikey
    assert_equal 403, last_response.status
  end

  def test_allow_post_writes
    begin
      acronym = "SECURE_ONT"
      params = {
        apikey: self.class.user2.apikey,
        acronym: acronym,
        name: "New test name",
        administeredBy: [self.class.user2.id.to_s]
      }
      post "/ontologies", MultiJson.dump(params), "CONTENT_TYPE" => "application/json"
      assert_equal 201, last_response.status
    ensure
      ont = LinkedData::Models::Ontology.find(acronym).first
      ont.delete(user: self.class.user2) if ont
      ont = LinkedData::Models::Ontology.find(acronym).first
      assert_nil ont
    end
  end

  def test_delete_access
    begin
      acronym = "SECURE_ONT_DEL" # must be <= 16 chars
      params = {
        apikey: self.class.user2.apikey,
        acronym: acronym,
        name: "New test name",
        administeredBy: [self.class.user2.id.to_s]
      }
      post "/ontologies", MultiJson.dump(params), "CONTENT_TYPE" => "application/json"
      assert_equal 201, last_response.status

      delete "/ontologies/#{acronym}?apikey=#{self.class.user.apikey}"
      assert_equal 403, last_response.status

      delete "/ontologies/#{acronym}?apikey=#{self.class.user2.apikey}"
      assert_equal 204, last_response.status
    ensure
      ont = LinkedData::Models::Ontology.find(acronym).first
      ont.delete(user: self.class.user2) if ont
      ont = LinkedData::Models::Ontology.find(acronym).first
      assert_nil ont
    end
  end

  def test_save_security_load_attributes
    # Ensure security-critical attrs aren’t overridden
    params = { apikey: self.class.user.apikey, administeredBy: [self.class.user2.id.to_s] }
    ont_url = "/ontologies/#{self.class.ont_patch.acronym}"
    patch ont_url, MultiJson.dump(params), "CONTENT_TYPE" => "application/json"
    assert_equal 204, last_response.status
    get ont_url, apikey: self.class.user2.apikey
    assert last_response.ok?
    ont = MultiJson.load(last_response.body)
    assert_includes ont["administeredBy"], self.class.user2.id.to_s
  end

  def test_write_access_denied
    params = { apikey: self.class.user2.apikey, name: "New test name" }
    patch "/ontologies/#{self.class.restricted_ont.acronym}", MultiJson.dump(params), "CONTENT_TYPE" => "application/json"
    assert_equal 403, last_response.status
  end

  def test_based_on_access
    get "/ontologies/#{self.class.restricted_ont.acronym}/submissions", apikey: self.class.user.apikey
    assert_equal 403, last_response.status
  end
end
