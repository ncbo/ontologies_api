require 'minitest/autorun'
require 'rack'
require 'rack/mock'
require_relative '../../lib/rack/trailing_slash_redirect'

# Backend-free unit tests for Rack::TrailingSlashRedirect. The middleware is
# driven directly with Rack::MockRequest -- no app boot, no triplestore / Solr
# / Redis required.
class TestTrailingSlashRedirect < Minitest::Test

  DOWNSTREAM = "downstream-app-response".freeze

  def setup
    @app = Rack::TrailingSlashRedirect.new(
      ->(_env) { [200, { 'content-type' => 'text/plain' }, [DOWNSTREAM]] }
    )
  end

  # Returns [status, location_header, body_string, env].
  def call(method, path, env_overrides = {})
    env = Rack::MockRequest.env_for(path, { method: method }.merge(env_overrides))
    status, headers, body = @app.call(env)
    buf = +''
    body.each { |chunk| buf << chunk }
    [status, headers['location'], buf, env]
  end

  def host(env)
    Rack::Request.new(env).host_with_port
  end

  # --- verb split: 301 for GET/HEAD, 308 for everything else -----------------

  def test_get_trailing_slash_redirects_301
    status, location, _body, env = call('GET', '/ontologies/STY/')
    assert_equal 301, status
    assert_equal "http://#{host(env)}/ontologies/STY", location
  end

  def test_non_get_verbs_redirect_308_preserving_location
    %w[POST PUT PATCH DELETE].each do |verb|
      status, location, _body, env = call(verb, '/mappings/')
      assert_equal 308, status,
                   "#{verb} must use 308 (301 would let clients drop the method/body)"
      assert_equal "http://#{host(env)}/mappings", location
    end
  end

  def test_head_trailing_slash_redirects_301_with_empty_body
    status, location, body, env = call('HEAD', '/ontologies/STY/')
    assert_equal 301, status
    assert_equal "http://#{host(env)}/ontologies/STY", location
    assert_equal '', body, 'a HEAD response must not carry a body'
  end

  # --- pass-through: no redirect for non-trailing-slash paths or root --------

  def test_no_trailing_slash_passes_through_untouched
    status, _location, body, = call('GET', '/ontologies/STY')
    assert_equal 200, status
    assert_equal DOWNSTREAM, body
  end

  def test_root_passes_through_untouched
    status, _location, body, = call('GET', '/')
    assert_equal 200, status
    assert_equal DOWNSTREAM, body
  end

  # --- location building: query, percent-encoding, forwarded scheme ----------

  def test_query_string_preserved
    _status, location, _body, env = call('GET', '/ontologies/STY/?apikey=xyz&include=all')
    assert_equal "http://#{host(env)}/ontologies/STY?apikey=xyz&include=all", location
  end

  def test_percent_encoded_path_segments_preserved
    enc = 'http%3A%2F%2Fpurl.bioontology.org%2Fontology%2FSTY%2FT071'
    _status, location, _body, env = call('GET', "/ontologies/STY/classes/#{enc}/paths_to_root/")
    assert_equal "http://#{host(env)}/ontologies/STY/classes/#{enc}/paths_to_root", location
  end

  def test_forwarded_proto_used_for_scheme
    _status, location, _body, env = call('GET', '/ontologies/STY/', 'HTTP_X_FORWARDED_PROTO' => 'https')
    assert_equal "https://#{host(env)}/ontologies/STY", location
  end

  def test_chained_forwarded_proto_uses_first_value
    _status, location, _body, env = call('GET', '/ontologies/STY/', 'HTTP_X_FORWARDED_PROTO' => 'https, http')
    assert_equal "https://#{host(env)}/ontologies/STY", location
  end

  def test_invalid_forwarded_proto_falls_back_to_request_scheme
    _status, location, _body, env = call('GET', '/ontologies/STY/', 'HTTP_X_FORWARDED_PROTO' => 'javascript')
    assert_equal "http://#{host(env)}/ontologies/STY", location
  end
end
