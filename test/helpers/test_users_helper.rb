require_relative '../test_case_helpers'

class TestUsersHelper < TestCaseHelpers

  def before_suite
    self.backend_4s_delete
    @@user = self.class._create_user
    @@non_custom_user = self.class._create_user("notcustom")

    @@onts = LinkedData::SampleData::Ontology.create_ontologies_and_submissions({
      ont_count: 5,
      submission_count: 0
    })[2]

    @@search_onts = LinkedData::SampleData::Ontology.create_ontologies_and_submissions({
      ont_count: 2,
      submission_count: 1,
      acronym: "PARSED",
      process_submission: true
    })[2]

    @@user_ont_search = @@search_onts.first
    @@user_ont = @@onts.first
    @@user.customOntology = [@@user_ont_search, @@user_ont]
    @@user.save

    @@custom_ont_ids = [@@user_ont_search.id.to_s, @@user_ont.id.to_s]

    @@old_security_setting = LinkedData.settings.enable_security
    LinkedData.settings.enable_security = true
  end

  def after_suite
    LinkedData.settings.enable_security = @@old_security_setting
  end

  def test_filtered_list
    get "/ontologies?apikey=#{@@user.apikey}"
    assert last_response.ok?
    onts = MultiJson.load(last_response.body)
    assert_equal onts.map {|o| o["@id"]}.sort, @@custom_ont_ids.sort
  end

  def test_search_custom_onts
    # Make sure group and non-group onts are in the search index
    get "/search?q=a*&pagesize=500&apikey=#{@@non_custom_user.apikey}"
    assert last_response.ok?
    results = MultiJson.load(last_response.body)["collection"]
    ont_ids = Set.new(results.map {|r| r["links"]["ontology"]})
    assert_equal ont_ids.to_a.sort, @@search_onts.map {|o| o.id.to_s}.sort

    # Do a search on the slice
    get "/search?q=a*&pagesize=500&apikey=#{@@user.apikey}"
    assert last_response.ok?
    results = MultiJson.load(last_response.body)["collection"]
    assert results.all? {|r| @@custom_ont_ids.include?(r["links"]["ontology"])}
  end

  def self._create_user(username = nil)
    username ||= "testuser"
    u = LinkedData::Models::User.new({
      username: username,
      email: "#{username}@example.com",
      password: "a_password"
    })
    u.save
    u
  end
end
