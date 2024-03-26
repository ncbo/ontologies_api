require 'multi_json'
require_relative '../test_case_helpers'

class TestApplicationHelper < TestCaseHelpers

  def before_suite
    @@ontologies = LinkedData::SampleData::Ontology.create_ontologies_and_submissions[2]
  end

  def test_it_escapes_html
    escaped_html = helper.h("<a>http://testlink.com</a>")
    assert escaped_html.eql?("&lt;a&gt;http:&#x2F;&#x2F;testlink.com&lt;&#x2F;a&gt;")
  end

  def test_ontologies_param
    ids = @@ontologies.map {|o| o.id.to_s}
    acronyms = @@ontologies.map {|o| o.id.to_s.split("/").last}
    params = {"ontologies" => acronyms.join(",")}
    ontologies = ontologies_param(params)
    assert ontologies == ids

    params = {"ontologies" => ids.join(",")}
    ontologies = ontologies_param(params)
    assert ontologies == ids

    id_acronym = ids + acronyms
    params = {"ontologies" => id_acronym.join(",")}
    ontologies = ontologies_param(params)
    assert ontologies == (ids + ids)
  end

  def test_ontology_uri_from_acronym
    @@ontologies.each do |ont|
      ont.bring(:acronym)
      uri = helper.ontology_uri_from_acronym(ont.acronym)
      assert uri == ont.id
    end
  end

  def test_acronym_from_ontology_uri
    @@ontologies.each do |ont|
      ont.bring(:acronym)
      acronym = helper.acronym_from_ontology_uri(ont.id)
      assert acronym == ont.acronym
    end
  end

  def test_bad_accept_header_handling
    # This accept header contains '*; q=.2', which isn't valid according to the spec, should be '*/*; q=.2'
    bad_accept_header = "text/html, image/gif, image/jpeg, *; q=.2, */*; q=.2"
    get "/ontologies", {}, {"HTTP_ACCEPT" => bad_accept_header}
    assert last_response.status == 400
    assert last_response.body.include?("Accept header `#{bad_accept_header}` is invalid")
  end

  def test_http_method_override
    post "/ontologies", {}, {"HTTP_X_HTTP_METHOD_OVERRIDE" => "GET"}
    assert last_response.ok?
    acronyms = @@ontologies.map {|o| o.bring(:acronym).acronym}.sort
    resp_acronyms = MultiJson.load(last_response.body).map {|o| o["acronym"]}.sort
    assert_equal acronyms, resp_acronyms
  end
end
