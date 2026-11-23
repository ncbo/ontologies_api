require 'cgi'
require_relative '../test_case'

# Regression: ncbo/bioportal-internal-tracker#33
# A Referer header used to stand in for an API key. The only requests served
# without a key now are the example links on the /documentation page.
class TestKeylessDocExamples < TestCase

  def test_list_matches_the_documentation_page
    get '/documentation'
    assert last_response.ok?, get_errors(last_response)

    examples = last_response.body.scan(/<a\b[^>]*>/).filter_map do |tag|
      next unless tag =~ /\sclass=(["'])[^"']*\bkeyless-example\b[^"']*\1/

      CGI.unescapeHTML(tag[/\shref=(["'])(.*?)\1/, 2])
    end
    refute_empty examples, 'no keyless-example links found on /documentation'

    assert_equal normalize(examples), normalize(KEYLESS_DOC_EXAMPLES),
                 'config/keyless_doc_examples.rb and the keyless-example links in ' \
                 'views/documentation/documentation.haml list different requests'
  end

  def test_examples_are_served_without_an_apikey
    with_settings(enable_security: true) do
      KEYLESS_DOC_EXAMPLES.each do |url|
        assert authorization_passes?(url), "#{url} needs an API key"
      end

      # through the whole application
      get '/search?q=melanoma'
      assert last_response.ok?, get_errors(last_response)
    end
  end

  def test_other_requests_need_an_apikey
    with_settings(enable_security: true) do
      [
        '/search',
        '/search?q=melanoma&page=2',
        '/search?q=melanoma&ontologies=NCIT',
        '/search?q=carcinoma',
        '/annotator?text=melanoma',
        '/analytics?month=5&year=2014',
        '/ontologies/NCIT',
        '/ontologies/GO/analytics',
        '/ontologies'
      ].each do |url|
        refute authorization_passes?(url), "#{url} was served without an API key"
        get url
        assert_equal 401, last_response.status, "#{url} was served without an API key"
      end

      post '/search?q=melanoma'
      assert_equal 401, last_response.status

      # parameters in a request body, which Rack::PostBodyToParams merges in
      get '/search?q=melanoma', {}, {
        'CONTENT_TYPE' => 'application/json',
        :input => '{"ontologies": "NCIT"}'
      }
      assert_equal 401, last_response.status
    end
  end

  def test_referer_does_not_replace_an_apikey
    with_settings(enable_security: true) do
      prefix = LinkedData.settings.rest_url_prefix
      # The request is for the host in the Referer, as it is when deployed.
      # (For any other host, Rack::Protection::JsonCsrf answers 403.)
      host = URI.parse(prefix).host
      [prefix, "#{prefix}documentation"].each do |referer|
        get '/ontologies', {}, { 'HTTP_REFERER' => referer, 'HTTP_HOST' => host }
        assert_equal 401, last_response.status, "Referer #{referer} replaced the API key"
      end
    end
  end

  private

  def normalize(urls)
    urls.map { |url| LinkedData::Security::Authorization.parse_keyless_request(url) }.sort_by(&:to_s)
  end

  # Runs the request through the authorization middleware alone, so that the
  # check doesn't depend on what each endpoint needs in order to answer.
  def authorization_passes?(url)
    reached = false
    endpoint = lambda do |_env|
      reached = true
      [200, { 'content-type' => 'text/plain' }, ['ok']]
    end
    middleware = LinkedData::Security::Authorization.new(endpoint, keyless_requests: KEYLESS_DOC_EXAMPLES)
    middleware.call(Rack::MockRequest.env_for(url))
    reached
  end
end
