require_relative '../test_case'

class TestPropertiesSearchController < TestCase

  def self.before_suite
    count, acronyms, bro = LinkedData::SampleData::Ontology.create_ontologies_and_submissions({
                                                                                                  process_submission: true,
                                                                                                  process_options:{process_rdf: true, extract_metadata: false, index_properties: true},
                                                                                                  acronym: "BROSEARCHTEST",
                                                                                                  name: "BRO Search Test",
                                                                                                  file_path: "./test/data/ontology_files/BRO_v3.2.owl",
                                                                                                  ont_count: 1,
                                                                                                  submission_count: 1,
                                                                                                  ontology_type: "VALUE_SET_COLLECTION"
                                                                                              })

    count, acronyms, mccl = LinkedData::SampleData::Ontology.create_ontologies_and_submissions({
                                                                                                   process_submission: true,
                                                                                                   process_options:{process_rdf: true, extract_metadata: false, index_properties: true},
                                                                                                   acronym: "MCCLSEARCHTEST",
                                                                                                   name: "MCCL Search Test",
                                                                                                   file_path: "./test/data/ontology_files/CellLine_OWL_BioPortal_v1.0.owl",
                                                                                                   ont_count: 1,
                                                                                                   submission_count: 1
                                                                                               })
    @@ontologies = bro.concat(mccl)
  end

  def self.after_suite
    LinkedData::SampleData::Ontology.delete_ontologies_and_submissions
    LinkedData::Models::Ontology.indexClear(:property)
    LinkedData::Models::Ontology.indexCommit(nil, :property)
  end

  def test_property_search
    get '/property_search?q=development_stage'
    assert last_response.ok?

    acronyms = @@ontologies.map { |ont| ont.bring_remaining; ont.acronym }
    results = MultiJson.load(last_response.body)

    results["collection"].each do |doc|
      acronym = doc["links"]["ontology"].split('/')[-1]
      assert acronyms.include?(acronym)
    end
  end

  def test_search_filters
    get '/property_search?q=contact person'
    assert last_response.ok?
    results = MultiJson.load(last_response.body)

    doc = results["collection"][0]
    assert_equal ["contact_person", "contact person"], doc["labelGenerated"]
    assert_equal 3, results["collection"].length

    get '/property_search?q=has'
    assert last_response.ok?
    results = MultiJson.load(last_response.body)
    assert_equal 17, results["collection"].length

    get '/property_search?q=has&ontologies=MCCLSEARCHTEST-0'
    assert last_response.ok?
    results = MultiJson.load(last_response.body)
    assert_equal 2, results["collection"].length

    get '/property_search?q=has&ontology_types=ONTOLOGY'
    assert last_response.ok?
    results = MultiJson.load(last_response.body)
    assert_equal 2, results["collection"].length

    get '/property_search?q=has&ontologies=BROSEARCHTEST-0&property_types=annotation'
    assert last_response.ok?
    results = MultiJson.load(last_response.body)
    assert_equal 2, results["collection"].length
  end
end
