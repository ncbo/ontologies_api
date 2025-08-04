require_relative '../test_case'

class TestSchemesController < TestCase

  def before_suite
    LinkedData::SampleData::Ontology.create_ontologies_and_submissions({
      process_submission: true,
      acronym: 'INRAETHES',
      name: 'INRAETHES',
      file_path: './test/data/ontology_files/thesaurusINRAE_nouv_structure.rdf',
      ont_count: 1,
      submission_count: 1
    })
  end

  def after_suite
    LinkedData::SampleData::Ontology.delete_ontologies_and_submissions
  end

  def test_schemes_all
    ont = Ontology.find('INRAETHES-0').include(:acronym).first

    call = "/ontologies/#{ont.acronym}/schemes"
    get call
    assert last_response.ok?
    schemes = MultiJson.load(last_response.body)
    assert last_response.ok?
    # Check default size
    assert_equal 66, schemes.size
  end




  def test_scheme
    ont = Ontology.find('INRAETHES-0').include(:acronym).first

    known_schemes = {
      "http://opendata.inrae.fr/thesaurusINRAE/mt_74": 'BIO neurosciences',
      "http://opendata.inrae.fr/thesaurusINRAE/domainesINRAE": 'INRAE domains',
    }

    known_schemes.each do |id, label|
      call = "/ontologies/#{ont.acronym}/schemes/#{CGI.escape(id.to_s)}"
      get call
      assert last_response.ok?
      instances = MultiJson.load(last_response.body)
      assert_equal label, instances["prefLabel"]
      assert_equal "http://www.w3.org/2004/02/skos/core#ConceptScheme", instances["@type"]
    end
  end

  def test_calls_not_found
    cls_id = CGI.escape('http://bad/invalid/no.good/class.id')

    get '/ontologies/BAD-ONT/schemes'
    assert_equal 404, last_response.status

    ont = Ontology.find('INRAETHES-0').include(:acronym).first
    get "ontologies/#{ont.acronym}/schemes/#{cls_id}"
    assert_equal 404, last_response.status
  end

end
