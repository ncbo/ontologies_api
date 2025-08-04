require_relative '../test_case'

class TestCollectionsController < TestCase

  def before_suite
    LinkedData::SampleData::Ontology.create_ontologies_and_submissions({
      process_submission: true,
      acronym: 'INRAETHES',
      name: 'INRAETHES',
      file_path: './test/data/ontology_files/thesaurusINRAE_nouv_structure.rdf',
      ont_count: 1,
      submission_count: 1
    })
    ont = Ontology.find('INRAETHES-0').include(:acronym).first
    sub = ont.latest_submission
    sub.bring_remaining
    sub.hasOntologyLanguage = LinkedData::Models::OntologyFormat.find('SKOS').first
    sub.save
  end

  def after_suite
    LinkedData::SampleData::Ontology.delete_ontologies_and_submissions
  end

  def test_collections_all
    ont = Ontology.find('INRAETHES-0').include(:acronym).first
    call = "/ontologies/#{ont.acronym}/collections"
    get call
    assert last_response.ok?
    collections = MultiJson.load(last_response.body)
    assert last_response.ok?
    # Check default size
    assert_equal 2, collections.size
  end


  def test_collection
    ont = Ontology.find('INRAETHES-0').include(:acronym).first

    known_collections = {
      "http://opendata.inrae.fr/thesaurusINRAE/gr_6c79e7c5": ["GR. DEFINED CONCEPTS" , 295],
      "http://opendata.inrae.fr/thesaurusINRAE/skosCollection_e25f9c62": ["GR. DISCIPLINES" , 233],
    }

    known_collections.each do |id, array|
      call = "/ontologies/#{ont.acronym}/collections/#{CGI.escape(id.to_s)}"
      get call
      assert last_response.ok?
      instances = MultiJson.load(last_response.body)
      assert_equal array[0], instances["prefLabel"]
      assert_equal array[1], instances["memberCount"]
      assert_equal "http://www.w3.org/2004/02/skos/core#Collection", instances["@type"]
    end
  end

  def test_collection_members
    ont = Ontology.find('INRAETHES-0').include(:acronym).first

    known_collections = {
      "http://opendata.inrae.fr/thesaurusINRAE/gr_6c79e7c5": ["GR. DEFINED CONCEPTS" , 295],
      "http://opendata.inrae.fr/thesaurusINRAE/skosCollection_e25f9c62": ["GR. DISCIPLINES" , 233],
    }

    known_collections.each do |id, array|
      call = "/ontologies/#{ont.acronym}/collections/#{CGI.escape(id.to_s)}/members?pagesize=1000"
      get call
      assert last_response.ok?
      instances = MultiJson.load(last_response.body)
      assert_equal array[1], instances['collection'].size
      assert_equal "http://www.w3.org/2004/02/skos/core#Concept", instances['collection'].first["@type"]
    end
  end

  def test_calls_not_found
    cls_id = CGI.escape('http://bad/invalid/no.good/class.id')

    get '/ontologies/BAD-ONT/collections'
    assert_equal 404, last_response.status


    ont = Ontology.find('INRAETHES-0').include(:acronym).first
    get "ontologies/#{ont.acronym}/collections/#{cls_id}"
    assert_equal 404, last_response.status
  end

end
