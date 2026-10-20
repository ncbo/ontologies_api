require_relative '../test_case'

class TestGroupsController < TestCase

  def setup
    @user = self.class.create_user('test-group-user')
    @admin = self.class.create_user('test-group-admin')
    self.class.make_admin(@admin)

    # Create some test groups
    @test_group = {acronym: "TEST-GROUP", name: "Test Group", description: "Description of the Test Group"}

    @groups = {
      "CTSA-HOM" => ["CTSA Health Ontology Mapper Cancer", "CTSA Health Ontology Mapper Cancer Description"],
      "caBIG" => ["Biomedical Informatics Grid", "Biomedical Info Grid Description"],
      "CTSA" => ["Clinical and Translational Science Awards", "CTSA Description"],
      "CGIAR" => ["Consultative Group on International Agricultural Research", "Consultative Group Description"],
      "OBOF" => ["OBO Foundry", "OBO Foundry Description"],
      "PSI" => ["Proteomics Standards Initiative", "Proteomics Group Description"],
      "UMLS" => ["Unified Medical Language System",  "UMLS Group Description"],
      "WHO-FIC" => ["WHO Family of International Classifications", "WHO Description"]
    }

    # Make sure these don't exist
    _delete_groups

    i = 0
    # Create them again
    @groups.each do |acronym, name_desc|
      group = Group.new(acronym: acronym, name: name_desc[0], description: name_desc[1])
      group.save if group.valid?
      i += 1
    end
  end

  def teardown
    # Delete groups
    _delete_groups
    @user.delete
    @admin.delete
  end

  def _delete_groups
    test_group = Group.find(@test_group[:acronym]).first
    test_group.delete unless test_group.nil?
    @groups.each do |acronym, name_desc|
      group = Group.find(acronym).first
      group.delete unless group.nil?
      assert Group.find(acronym).first.nil?
    end
  end

  def test_all_groups
    get '/groups'
    assert last_response.ok?
    groups = MultiJson.load(last_response.body)
    assert groups.length >= @groups.length
  end

  def test_single_group
    acronym = 'CTSA'
    get "/groups/#{acronym}"
    assert last_response.ok?
    group = MultiJson.load(last_response.body)
    assert_equal acronym, group["acronym"]
  end

  def test_create_group_with_post_requires_admin
    assert_group_creation_requires_admin(:post, '/groups')
  end

  def test_create_group_with_put_requires_admin
    assert_group_creation_requires_admin(:put, "/groups/#{@test_group[:acronym]}")
  end

  def test_update_patch_group
    acronym = 'CTSA-HOM'
    group = Group.find(acronym).first
    assert_instance_of Group, group
    new_name = "CTSA Health Brand new NAME"
    new_desc = "CTSA Health Brand new DESCRIPTION"
    new_values = {name: new_name, description: new_desc}

    with_settings(enable_security: true) do
      patch "/groups/#{acronym}?apikey=#{@user.apikey}", MultiJson.dump(new_values), "CONTENT_TYPE" => "application/json"
      assert_equal 403, last_response.status
      unchanged = Group.find(acronym).include(:name, :description).first
      assert_equal @groups[acronym], [unchanged.name, unchanged.description]

      patch "/groups/#{acronym}?apikey=#{@admin.apikey}", MultiJson.dump(new_values), "CONTENT_TYPE" => "application/json"
      assert_equal 204, last_response.status

      get "/groups/#{acronym}?apikey=#{@user.apikey}"
      assert last_response.ok?
      group = MultiJson.load(last_response.body)
      assert_equal new_name, group["name"]
      assert_equal new_desc, group["description"]
    end
  end

  def test_delete_group
    acronym = 'CTSA-HOM'
    with_settings(enable_security: true) do
      delete "/groups/#{acronym}?apikey=#{@user.apikey}"
      assert_equal 403, last_response.status
      refute_nil Group.find(acronym).first

      delete "/groups/#{acronym}?apikey=#{@admin.apikey}"
      assert_equal 204, last_response.status

      get "/groups/#{acronym}?apikey=#{@user.apikey}"
      assert_equal 404, last_response.status
    end
  end

  private

  def assert_group_creation_requires_admin(method, path)
    acronym = @test_group[:acronym]
    with_settings(enable_security: true) do
      public_send(method, path, MultiJson.dump(@test_group), "CONTENT_TYPE" => "application/json")
      assert_equal 401, last_response.status
      assert_nil Group.find(acronym).first

      public_send(method, "#{path}?apikey=#{@user.apikey}", MultiJson.dump(@test_group), "CONTENT_TYPE" => "application/json")
      assert_equal 403, last_response.status
      assert_nil Group.find(acronym).first

      public_send(method, "#{path}?apikey=#{@admin.apikey}", MultiJson.dump(@test_group), "CONTENT_TYPE" => "application/json")
      assert_equal 201, last_response.status
      assert_equal acronym, MultiJson.load(last_response.body)["acronym"]

      get "/groups/#{acronym}?apikey=#{@user.apikey}"
      assert last_response.ok?
      assert_equal acronym, MultiJson.load(last_response.body)["acronym"]
    end
  end
end
