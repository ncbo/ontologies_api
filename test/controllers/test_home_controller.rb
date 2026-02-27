require_relative '../test_case'

class TestHomeController < TestCase
  def test_home_index_returns_links_hash
    get '/'
    assert last_response.ok?, get_errors(last_response)

    body = MultiJson.load(last_response.body)
    assert body.key?('links')
    assert_kind_of Hash, body['links']
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
