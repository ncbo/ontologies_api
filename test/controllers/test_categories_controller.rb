require_relative '../test_case'
require "multi_json"

class TestCategoriesController < TestCase

  def setup
    @user = self.class.create_user('test-category-user')
    @admin = self.class.create_user('test-category-admin')
    self.class.make_admin(@admin)

    # Create some test categories
    @test_cat = {acronym: "TEST-CAT", name: "Test Category", description: "Description of the Test Category"}

    @cats = {
        "ANAT" => ["Anatomy", "Anatomy Category Description"],
        "ANIMAL-DEV" => ["Animal Development", "Animal Development Category Description"],
        "AGA" => ["Animal Gross Anatomy", "Description for Animal Gross Anatomy"],
        "ARABADOPSIS" => ["Arabadopsis", "Arabadopsis Category Description"],
        "BP" => ["Biological Process", "Biological Process Category Description"],
        "BR" => ["Biomedical Resources", "Description of Biomedical Resources Category"],
        "CELL" => ["Cell", "Cell Category Description"]
    }

    # Make sure these don't exist
    _delete_categories

    i = 0
    # Create them again
    @cats.each do |acronym, name_desc|
      category = Category.new(acronym: acronym, name: name_desc[0], description: name_desc[1])
      category.save if category.valid?
      i += 1
    end
  end

  def teardown
    # Delete categories
    _delete_categories
    @user.delete
    @admin.delete
  end

  def _delete_categories
    test_cat = Category.find(@test_cat[:acronym]).first
    test_cat.delete unless test_cat.nil?

    @cats.each do |acronym, name_desc|
      cat = Category.find(acronym).first
      cat.delete unless cat.nil?
      assert Category.find(acronym).nil?
    end
  end

  def test_all_categories
    get '/categories'
    assert last_response.ok?

    categories = MultiJson.load(last_response.body)
    all_acronyms = []
    categories.each do |returned_cat|
      all_acronyms << returned_cat["acronym"]
    end

    @cats.each do |acronym, name_desc|
      assert all_acronyms.include?(acronym)
    end
  end

  def test_single_category
    @cats.each do |acronym, name_desc|
      get "/categories/#{acronym}"
      assert last_response.ok?
      category = MultiJson.load(last_response.body)
      assert_equal acronym, category["acronym"]
    end
  end

  def test_create_category_with_post_requires_admin
    assert_category_creation_requires_admin(:post, '/categories')
  end

  def test_create_category_with_put_requires_admin
    assert_category_creation_requires_admin(:put, "/categories/#{@test_cat[:acronym]}")
  end

  def test_update_patch_category
    acronym = 'ANAT'
    category = Category.find(acronym).first
    assert_instance_of Category, category
    new_name = "Anatomyzation new NAME"
    new_desc = "Anatomyzation new DESCRIPTION"
    new_values = {name: new_name, description: new_desc}

    with_settings(enable_security: true) do
      patch "/categories/#{acronym}?apikey=#{@user.apikey}", MultiJson.dump(new_values), "CONTENT_TYPE" => "application/json"
      assert_equal 403, last_response.status
      unchanged = Category.find(acronym).include(:name, :description).first
      assert_equal @cats[acronym], [unchanged.name, unchanged.description]

      patch "/categories/#{acronym}?apikey=#{@admin.apikey}", MultiJson.dump(new_values), "CONTENT_TYPE" => "application/json"
      assert_equal 204, last_response.status

      get "/categories/#{acronym}?apikey=#{@user.apikey}"
      assert last_response.ok?
      category = MultiJson.load(last_response.body)
      assert_equal new_name, category["name"]
      assert_equal new_desc, category["description"]
    end
  end

  def test_delete_category
    acronym = 'ANAT'
    with_settings(enable_security: true) do
      delete "/categories/#{acronym}?apikey=#{@user.apikey}"
      assert_equal 403, last_response.status
      refute_nil Category.find(acronym).first

      delete "/categories/#{acronym}?apikey=#{@admin.apikey}"
      assert_equal 204, last_response.status

      get "/categories/#{acronym}?apikey=#{@user.apikey}"
      assert_equal 404, last_response.status
    end
  end

  private

  def assert_category_creation_requires_admin(method, path)
    acronym = @test_cat[:acronym]
    with_settings(enable_security: true) do
      public_send(method, path, MultiJson.dump(@test_cat), "CONTENT_TYPE" => "application/json")
      assert_equal 401, last_response.status
      assert_nil Category.find(acronym).first

      public_send(method, "#{path}?apikey=#{@user.apikey}", MultiJson.dump(@test_cat), "CONTENT_TYPE" => "application/json")
      assert_equal 403, last_response.status
      assert_nil Category.find(acronym).first

      public_send(method, "#{path}?apikey=#{@admin.apikey}", MultiJson.dump(@test_cat), "CONTENT_TYPE" => "application/json")
      assert_equal 201, last_response.status
      assert_equal acronym, MultiJson.load(last_response.body)["acronym"]

      get "/categories/#{acronym}?apikey=#{@user.apikey}"
      assert last_response.ok?
      assert_equal acronym, MultiJson.load(last_response.body)["acronym"]
    end
  end
end
