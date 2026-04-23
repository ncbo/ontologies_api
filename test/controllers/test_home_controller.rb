require_relative '../test_case'

class TestHomeController < TestCase
  def test_home_index_returns_links_hash
    get '/'
    assert last_response.ok?, get_errors(last_response)

    body = MultiJson.load(last_response.body)
    assert body.key?('links')
    assert_kind_of Hash, body['links']
    assert body['links'].key?('@context')
    assert_kind_of Hash, body['links']['@context']
    assert_operator body['links']['@context'].length, :>, 0
  end

  # Regression: ncbo/ontologies_api#212
  # Under sinatra-contrib 4.2.1, `namespace "/"`'s before-filter pattern
  # does not match sub-paths, so helpers defined inside the namespace
  # block are not mixed into the request instance and the route handler
  # raises NameError: undefined local variable or method `metadata_all'.
  def test_documentation_route_renders
    get '/documentation'
    assert last_response.ok?, get_errors(last_response)
    assert_match(/<html/i, last_response.body)
  end

  # Regression: ncbo/ontologies_api#212 / #37
  # Valid `/metadata/:class` paths were 500-ing under sinatra-contrib 4.2.1
  # for the same namespace-helper-resolution reason as /documentation, and
  # had been listed as broken in #37 since 2017.
  def test_metadata_route_renders_for_model_class
    get '/metadata/Metrics'
    assert last_response.ok?, get_errors(last_response)
    assert_match(/<html/i, last_response.body)
  end

  # Exercises the sub-module lookup branch in HomeHelper#routes_by_class
  # (LinkedData::Models::Notes::Reply rather than a top-level model).
  def test_metadata_route_resolves_submodule_class
    get '/metadata/Reply'
    assert last_response.ok?, get_errors(last_response)
    assert_match(/<html/i, last_response.body)
  end

  # /metadata/:class for names that aren't model classes (attribute/property
  # names, arbitrary typos) should return 404, not 500. Several paths of this
  # shape are listed in ncbo/ontologies_api#37.
  def test_metadata_route_returns_404_for_non_class_names
    %w[created body prefixIRI name omvacronym Nonexistent].each do |name|
      get "/metadata/#{name}"
      assert_equal 404, last_response.status,
        "expected 404 for /metadata/#{name}, got #{last_response.status}: #{last_response.body[0, 200]}"
      assert_match(/not a documented media type/i, last_response.body,
        "expected /metadata/#{name} 404 body to mention 'media type'; got: #{last_response.body[0, 200]}")
    end
  end

  def test_home_index_handles_type_uri_failures
    bad_class = Class.new do
      def self.type_uri
        raise NoMethodError, 'model settings missing'
      end
    end

    klass = Sinatra::Application
    original_routes_list = klass.instance_method(:routes_list) rescue nil
    original_route_to_class_map = klass.instance_method(:route_to_class_map) rescue nil

    klass.class_eval do
      define_method(:routes_list) { ['/broken'] }
      define_method(:route_to_class_map) { { '/broken' => bad_class } }
    end

    get '/'
    assert last_response.ok?, get_errors(last_response)
  ensure
    klass.class_eval do
      if original_routes_list
        define_method(:routes_list, original_routes_list)
      else
        remove_method(:routes_list) rescue nil
      end

      if original_route_to_class_map
        define_method(:route_to_class_map, original_route_to_class_map)
      else
        remove_method(:route_to_class_map) rescue nil
      end
    end
  end
end
