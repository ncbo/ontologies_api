require_relative '../test_case'

class TestInstancesController < TestCase

  def before_suite
    LinkedData::SampleData::Ontology.create_ontologies_and_submissions({
                                                                         process_submission: true,
                                                                         process_options: { process_rdf: true, extract_metadata: false, generate_missing_labels: false},
                                                                         acronym: 'XCT-TEST-INST',
                                                                         name: 'XCT-TEST-INST',
                                                                         file_path: './test/data/ontology_files/XCTontologyvtemp2.owl',
                                                                         ont_count: 1,
                                                                         submission_count: 1
                                                                       })
  end


  def test_first_default_page
    ont = Ontology.find('XCT-TEST-INST-0').include(:acronym).first

    call = "/ontologies/#{ont.acronym}/instances"
    get call
    assert last_response.ok?
    instances = MultiJson.load(last_response.body)
    assert last_response.ok?
    # Check default size
    assert_equal 50, instances['collection'].size
  end

  def test_all_instance_pages
    ont = Ontology.find('XCT-TEST-INST-0').include(:acronym).first

    response = nil
    instance_count = 0
    page_count = nil
    begin
      call = "/ontologies/#{ont.acronym}/instances?include=all"
      if response
        page_count = response['nextPage']
        call <<  "&page=#{response['nextPage']}"
      end
      get call
      assert last_response.ok?
      response = MultiJson.load(last_response.body)
      response['collection'].each do |inst|
        assert inst['@id'].instance_of? String
        assert inst['label'].instance_of? Array
        assert inst['properties'].instance_of? Hash
      end
      assert last_response.ok?
      instance_count = instance_count + response['collection'].size
    end while response['nextPage']

    assert_equal 714, instance_count

    # Next page should have no results.
    call = "/ontologies/#{ont.acronym}/instances"
    call <<  "?page=#{page_count + 1}"
    get call
    assert last_response.ok?
    response = MultiJson.load(last_response.body)
    assert response['collection'].length == 0
  end

  def test_instances_for_class
    ont = Ontology.find('XCT-TEST-INST-0').include(:acronym).first

    known_instances = {}
    known_instances['http://www.owl-ontologies.com/OntologyXCT.owl#MedicalResearchCouncilGradeMusclePower'] = [
      'http://www.owl-ontologies.com/OntologyXCT.owl#MedicalResearchCouncilGrade0',
      'http://www.owl-ontologies.com/OntologyXCT.owl#MedicalResearchCouncilGrade1',
      'http://www.owl-ontologies.com/OntologyXCT.owl#MedicalResearchCouncilGrade2',
      'http://www.owl-ontologies.com/OntologyXCT.owl#MedicalResearchCouncilGrade3',
      'http://www.owl-ontologies.com/OntologyXCT.owl#MedicalResearchCouncilGrade4',
      'http://www.owl-ontologies.com/OntologyXCT.owl#MedicalResearchCouncilGrade5'
    ]
    known_instances['http://www.owl-ontologies.com/OntologyXCT.owl#Study'] = [
      'http://www.owl-ontologies.com/OntologyXCT.owl#Arpa',
      'http://www.owl-ontologies.com/OntologyXCT.owl#Bel',
      'http://www.owl-ontologies.com/OntologyXCT.owl#BMCNeurology',
      'http://www.owl-ontologies.com/OntologyXCT.owl#Campdelacreu',
      'http://www.owl-ontologies.com/OntologyXCT.owl#Cuende',
      'http://www.owl-ontologies.com/OntologyXCT.owl#MalodeMolina',
      'http://www.owl-ontologies.com/OntologyXCT.owl#Tesis',
      'http://www.owl-ontologies.com/OntologyXCT.owl#Verrips',
    ]

    cls_ids = [
      'http://www.owl-ontologies.com/OntologyXCT.owl#MedicalResearchCouncilGradeMusclePower',
      'http://www.owl-ontologies.com/OntologyXCT.owl#Study'
    ]
    cls_ids.each do |cls_id|
      call = "/ontologies/#{ont.acronym}/classes/#{CGI.escape(cls_id)}/instances"
      get call
      assert last_response.ok?
      instances = MultiJson.load(last_response.body)['collection']
      instances.map! { |inst| inst["@id"] }
      assert_equal known_instances[cls_id].sort, instances.sort
    end
  end

  def test_calls_not_found
    cls_id = CGI.escape('http://bad/invalid/no.good/class.id')

    get '/ontologies/BAD-ONT/instances'
    assert_equal 404, last_response.status

    get "ontologies/BAD-ONT/classes/#{cls_id}/instances"
    assert_equal 404, last_response.status

    ont = Ontology.find('XCT-TEST-INST-0').include(:acronym).first
    get "ontologies/#{ont.acronym}/classes/#{cls_id}/instances"
    assert_equal 404, last_response.status
  end

end