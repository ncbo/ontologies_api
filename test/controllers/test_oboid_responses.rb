require 'minitest/autorun'
require 'rack/test'
require 'sinatra'
require 'sinatra/namespace'
Sinatra::Application.set :run, false
require 'ontologies_linked_data'
require_relative '../../lib/rack/param_translator'
require_relative '../../helpers/application_helper'
require_relative '../../helpers/pagination_helper'
require_relative '../../helpers/search_helper'
require_relative '../../helpers/classes_helper'
require_relative '../../controllers/application_controller'
require_relative '../../controllers/search_controller'
require_relative '../../controllers/classes_controller'

# Exercise the real routes, include translation, helpers, and serializer without
# booting the full app or clearing a database. Only persistence/access lookups
# are replaced; search document conversion and class loading plans stay real.
class TestOboIdResponses < Minitest::Test
  include Rack::Test::Methods

  CLASS = LinkedData::Models::Class
  NCIT_IRI = 'http://ncicb.nci.nih.gov/xml/owl/EVS/Thesaurus.owl'.freeze
  CLASS_IRI = "#{NCIT_IRI}#C20047".freeze

  class App < Sinatra::Application
    set :environment, :test
    set :run, false
    set :show_exceptions, false
    set :raise_errors, true
    set :protection, except: :path_traversal
    use Rack::ParamTranslator

    helpers do
      def restricted_ontologies(_params = nil)
        []
      end

      def restricted_ontologies_to_acronyms(*_args)
        []
      end

      def filter_for_user_onts(object)
        object
      end

      def get_ontology_and_submission
        submission = env.fetch('test.submission')
        [submission.ontology, submission]
      end

      def check_last_modified_segment(*_args); end
    end
  end

  def app
    App
  end

  def setup
    @settings = { enable_security: false, enable_slices: false, enable_http_cache: false,
                  rest_url_prefix: 'http://data.bioontology.org/', ui_host: 'bioportal.bioontology.org' }
    @previous_settings = @settings.to_h { |key, _| [key, LinkedData.settings.public_send(key)] }
    @settings.each { |key, value| LinkedData.settings.public_send("#{key}=", value) }
  end

  def teardown
    @previous_settings.each { |key, value| LinkedData.settings.public_send("#{key}=", value) }
  end

  def test_search_defaults_include_stored_identifier_and_metadata
    result = search_response
    cls = result.fetch('collection').first

    assert_equal 'NCIT:C20047', cls['oboId']
    assert_metadata(cls)
    assert_equal CLASS_IRI, cls['@id']
    assert cls.key?('@context')
    assert cls.key?('links')
    assert_equal 1, result['page']
    assert_equal 1, result['totalCount']
  end

  def test_post_search_can_select_identifier_notation_and_metadata_together
    result = search_response(
      { 'include' => 'prefLabel,notation,oboId,obsolete,matchType,ontologyType,provisional' }, method: :post
    ).fetch('collection').first

    assert_equal 'NCIT:C20047', result['oboId']
    assert_equal 'Thesaurus:C20047', result['notation']
    assert_metadata(result)
  end

  def test_explicit_includes_still_replace_defaults
    result = search_response({ 'include' => 'oboId' }).fetch('collection').first
    assert_equal 'NCIT:C20047', result['oboId']
    refute result.key?('prefLabel')
    refute result.key?('obsolete')
    assert result.key?('@id')

    result = search_response({ 'include' => 'prefLabel' }).fetch('collection').first
    refute result.key?('oboId')
  end

  def test_unknown_includes_remain_invalid
    %w[unsupportedField all].each do |field|
      search_response({ 'include' => field }, status: 400)
      assert_includes last_response.body, "cannot accept #{field}"
    end
  end

  def test_search_does_not_derive_or_substitute_missing_stored_identifiers
    doc = search_doc('resource_id' => 'http://purl.obolibrary.org/obo/GO_0050892')
    doc.delete('oboId')
    result = search_response({}, docs: [doc]).fetch('collection').first

    refute result.key?('oboId'), 'Even an OBO IRI must use the stored search field'
    assert_equal 'Label', result['prefLabel']
  end

  def test_provisional_results_without_an_identifier_remain_valid
    doc = search_doc('provisional' => true)
    doc.delete('oboId')
    result = search_response(
      { 'also_search_provisional' => 'true', 'include' => 'prefLabel,oboId,obsolete,provisional' }, docs: [doc]
    ).fetch('collection').first

    assert_equal true, result['provisional']
    assert_equal false, result['obsolete']
    refute result.key?('oboId')
  end

  def test_include_selection_does_not_change_search_weights_or_filters
    [{}, { 'exact_match' => 'true' }, { 'suggest' => 'true' }].each do |mode|
      search_response(mode)
      baseline = @search_params.slice('qf', 'bq', 'boost', 'fq', 'fl')
      search_response(mode.merge('include' => 'prefLabel,oboId,obsolete,matchType,ontologyType,provisional'))
      assert_equal baseline, @search_params.slice('qf', 'bq', 'boost', 'fq', 'fl')
      assert_equal '*,score', @search_params['fl']
    end
  end

  def test_pagination_and_optional_hypermedia_are_preserved
    result = search_response({ 'pagesize' => '1', 'display_links' => 'false', 'display_context' => 'false' }, total: 2)

    assert_equal 2, result['pageCount']
    assert_equal 2, result['nextPage']
    refute result['collection'].first.key?('links')
    refute result['collection'].first.key?('@context')
    assert_equal 'NCIT:C20047', result['collection'].first['oboId']
  end

  def test_class_details_and_search_agree_for_ncit
    result = class_response
    indexed = search_response.fetch('collection').first

    assert_equal 'NCIT:C20047', result['oboId']
    assert_equal indexed['oboId'], result['oboId']
    assert_equal false, result['obsolete']
    assert result.key?('@context')
    assert result.key?('links')
    submission_attrs = @class_includes.find { |attr| attr.is_a?(Hash) && attr.key?(:submission) }[:submission]
    assert_includes submission_attrs, :uri
  end

  def test_class_details_support_explicit_identifier_and_notation_selection
    result = class_response({ 'include' => 'oboId,notation,obsolete' })

    assert_equal 'NCIT:C20047', result['oboId']
    assert_equal 'Thesaurus:C20047', result['notation']
    assert_equal false, result['obsolete']
    refute result.key?('prefLabel')
  end

  def test_imported_terms_retain_their_prefix_in_class_details
    result = class_response({}, iri: 'http://purl.obolibrary.org/obo/CHEBI_46195')

    assert_equal 'CHEBI:46195', result['oboId']
  end

  def test_class_details_omit_identifiers_that_cannot_be_derived
    result = class_response({}, iri: 'http://external.example.org/word')

    refute result.key?('oboId')
    assert_equal 'Label', result['prefLabel']
  end

  private

  def assert_metadata(cls)
    assert_equal 'Label', cls['prefLabel']
    assert_equal false, cls['obsolete']
    assert_equal 'prefLabel', cls['matchType']
    assert_equal 'ONTOLOGY', cls['ontologyType']
    assert_equal false, cls['provisional']
  end

  def search_doc(overrides = {})
    { 'id' => 'solr-document-id', 'resource_id' => CLASS_IRI,
      'ontologyId' => 'http://data.bioontology.org/ontologies/NCIT/submissions/1',
      'submissionAcronym' => 'NCIT', 'prefLabel' => ['Label'], 'notation' => 'Thesaurus:C20047',
      'oboId' => 'NCIT:C20047', 'obsolete' => false, 'ontologyType' => 'ONTOLOGY',
      'provisional' => false }.merge(overrides)
  end

  def search_response(params = {}, method: :get, docs: [search_doc], status: 200, total: docs.size)
    search = lambda do |_query, solr_params|
      @search_params = solr_params.dup
      { 'response' => { 'numFound' => total, 'docs' => docs },
        'highlighting' => docs.to_h { |doc| [doc['id'], { 'prefLabel' => ['<em>Label</em>'] }] } }
    end
    with_method(CLASS, :search, search) do
      without_triplestore do
        public_send(method, '/search', { 'q' => 'NCIT:C20047' }.merge(params))
      end
    end
    assert_equal status, last_response.status, last_response.body
    MultiJson.load(last_response.body)
  end

  def class_response(params = {}, iri: CLASS_IRI)
    ontology = LinkedData::Models::Ontology.new(acronym: 'NCIT')
    submission = LinkedData::Models::OntologySubmission.new(
      id: RDF::URI.new('http://data.bioontology.org/ontologies/NCIT/submissions/1'),
      ontology: ontology, uri: RDF::URI.new(NCIT_IRI), naturalLanguage: [],
      hasOntologyLanguage: LinkedData::Models::OntologyFormat.new(acronym: 'OWL')
    )
    cls = CLASS.new(id: RDF::URI.new(iri), submission: submission, prefLabel: 'Label',
                    notation: 'Thesaurus:C20047', obsolete: false)
    query = CLASS.find(cls.id).in(submission)
    include_attributes = query.method(:include)
    capture_includes = ->(attrs) { @class_includes = attrs; include_attributes.call(attrs) }
    query.define_singleton_method(:include) { |attrs| capture_includes.call(attrs) }
    query.define_singleton_method(:first) { cls }

    with_method(CLASS, :find, ->(id) { assert_equal iri, id.to_s; query }) do
      with_method(CLASS, :search, ->(*) { flunk 'Class details must not query Solr for oboId' }) do
        without_triplestore do
          get "/ontologies/NCIT/classes/#{CGI.escape(iri)}", params, 'test.submission' => submission
        end
      end
    end
    assert_equal 200, last_response.status, last_response.body
    MultiJson.load(last_response.body)
  end

  def without_triplestore(&block)
    with_method(Goo, :main_languages, -> { [:en] }) do
      with_method(Goo, :sparql_query_client, ->(*) { flunk 'Unexpected triplestore query' }, &block)
    end
  end

  def with_method(object, name, implementation)
    original = object.method(name)
    object.define_singleton_method(name) { |*args, **kwargs, &block| implementation.call(*args, **kwargs, &block) }
    yield
  ensure
    object.define_singleton_method(name, original)
  end
end
