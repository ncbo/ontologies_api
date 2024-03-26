require_relative '../test_case_helpers'

class TestAccessControlHelper < TestCaseHelpers

  def before_suite
    self.backend_4s_delete

    @@usernames = ["user1", "user2", "user3", "admin"]
    @@usernames.each do |username|
      user = LinkedData::Models::User.new(
        username: username,
        email: "#{username}@example.org",
        password: "note_user_pass"
      )
      user.save
      user.bring_remaining
      self.class.class_variable_set(:"@@#{username}", user)
    end

    @@admin.role = [LinkedData::Models::Users::Role.find(LinkedData::Models::Users::Role::ADMIN).first]
    @@admin.save

    onts = LinkedData::SampleData::Ontology.create_ontologies_and_submissions[2]

    @@restricted_ont = onts.shift
    @@restricted_ont.bring_remaining
    @@restricted_ont.viewingRestriction = "private"
    @@restricted_ont.acl = [@@user2, @@user3]
    @@restricted_ont.administeredBy = [@@user1]
    @@restricted_ont.save
    @@restricted_user = @@restricted_ont.administeredBy.first
    @@restricted_user.bring_remaining

    @@ont = onts.shift
    @@ont.bring_remaining
    @@user = @@ont.administeredBy.first
    @@user.bring_remaining
    @@old_security_setting = LinkedData.settings.enable_security

    @@ont_patch = onts.shift.bring_remaining

    LinkedData.settings.enable_security = true
  end

  def after_suite
    self.backend_4s_delete
    LinkedData.settings.enable_security = @@old_security_setting unless @@old_security_setting.nil?
  end

  def test_filtered_list
    get "/ontologies", apikey: @@user.apikey
    onts = MultiJson.load(last_response.body)
    assert last_response.ok?
    assert onts.length == 4
    assert onts.any? {|o| o["@id"] == @@ont.id.to_s}
    refute onts.any? {|o| o["@id"] == @@restricted_ont.id.to_s}
  end

  def test_direct_access
    get "/ontologies/#{@@restricted_ont.acronym}", apikey: @@user.apikey
    assert last_response.status == 403
  end

  def test_allow_post_writes
    begin
      acronym = "SECURE_ONT"
      params = {apikey: @@user2.apikey, acronym: acronym, name: "New test name", administeredBy: [@@user2.id.to_s]}
      post "/ontologies", MultiJson.dump(params), "CONTENT_TYPE" => "application/json"
      assert last_response.status == 201
    ensure
      ont = LinkedData::Models::Ontology.find(acronym).first
      ont.delete(user: @@user2) if ont
      ont = LinkedData::Models::Ontology.find(acronym).first
      assert ont.nil?
    end
  end

  def test_delete_access
    begin
      acronym = "SECURE_ONT_DEL" # must be <= 16 chars
      params = {apikey: @@user2.apikey, acronym: acronym, name: "New test name", administeredBy: [@@user2.id.to_s]}
      post "/ontologies", MultiJson.dump(params), "CONTENT_TYPE" => "application/json"
      assert last_response.status == 201
      delete "/ontologies/#{acronym}?apikey=#{@@user.apikey}"
      assert last_response.status == 403
      delete "/ontologies/#{acronym}?apikey=#{@@user2.apikey}"
      assert last_response.status == 204
    ensure
      ont = LinkedData::Models::Ontology.find(acronym).first
      ont.delete(user: @@user2) if ont
      ont = LinkedData::Models::Ontology.find(acronym).first
      assert ont.nil?
    end
  end

  def test_save_security_load_attributes
    # We should make sure that attributes that are needed for security checks don't get overridden
    params = {apikey: @@user.apikey, administeredBy: [@@user2.id.to_s]}
    ont_url = "/ontologies/#{@@ont_patch.acronym}"
    patch ont_url, MultiJson.dump(params), "CONTENT_TYPE" => "application/json"
    assert last_response.status == 204
    get ont_url, apikey: @@user2.apikey
    assert last_response.ok?
    ont = MultiJson.load(last_response.body)
    assert ont["administeredBy"].include?(@@user2.id.to_s)
  end

  def test_write_access_denied
    params = {apikey: @@user2.apikey, name: "New test name"}
    patch "/ontologies/#{@@restricted_ont.acronym}", MultiJson.dump(params), "CONTENT_TYPE" => "application/json"
    assert last_response.status == 403
  end

  def test_based_on_access
    get "/ontologies/#{@@restricted_ont.acronym}/submissions", apikey: @@user.apikey
    assert last_response.status == 403
  end
end
