require_relative '../test_case'

class TestPropertiesController < TestCase

  def before_suite
    count, acronyms, bro = LinkedData::SampleData::Ontology.create_ontologies_and_submissions({
                                                                                                  process_submission: true,
                                                                                                  process_options:{process_rdf: true, extract_metadata: false},
                                                                                                  acronym: "BROSEARCHTEST",
                                                                                                  name: "BRO Search Test",
                                                                                                  file_path: "./test/data/ontology_files/BRO_v3.2.owl",
                                                                                                  ont_count: 1,
                                                                                                  submission_count: 1,
                                                                                                  ontology_type: "VALUE_SET_COLLECTION"
                                                                                              })

    count, acronyms, mccl = LinkedData::SampleData::Ontology.create_ontologies_and_submissions({
                                                                                                   process_submission: true,
                                                                                                   process_options:{process_rdf: true, extract_metadata: true},
                                                                                                   acronym: "MCCLSEARCHTEST",
                                                                                                   name: "MCCL Search Test",
                                                                                                   file_path: "./test/data/ontology_files/CellLine_OWL_BioPortal_v1.0.owl",
                                                                                                   ont_count: 1,
                                                                                                   submission_count: 1
                                                                                               })
    @@ontologies = bro.concat(mccl)
    @@acronyms = @@ontologies.map { |ont| ont.bring_remaining; ont.acronym }
  end

  def after_suite
    LinkedData::SampleData::Ontology.delete_ontologies_and_submissions
  end

  def test_properties
    get "/ontologies/#{@@acronyms.first}/properties"
    assert last_response.ok?
    results = MultiJson.load(last_response.body)
    assert_equal 85, results.length

    get "/ontologies/#{@@acronyms.last}/properties"
    assert last_response.ok?
    results = MultiJson.load(last_response.body)
    assert_equal 35, results.length
  end

  def test_single_property
    get "/ontologies/#{@@acronyms.first}/properties/http%3A%2F%2Fbioontology.org%2Fontologies%2FBiomedicalResourceOntology.owl%23Originator"
    assert last_response.ok?
    results = MultiJson.load(last_response.body)
    assert results.is_a?(Hash)
    assert_equal ["Originator"], results["label"]
    assert_equal "http://bioontology.org/ontologies/BiomedicalResourceOntology.owl#Originator", results["@id"]

    get "/ontologies/#{@@acronyms.first}/properties/http%3A%2F%2Fbioontology.org%2Fontologies%2FBiomedicalResourceOntology.owl%23DummyProp"
    assert_equal 404, last_response.status
  end

  def test_property_roots
    get "/ontologies/#{@@acronyms.first}/properties/roots"
    assert last_response.ok?
    pr = MultiJson.load(last_response.body)
    assert_equal 62, pr.length

    # count object properties
    opr = pr.select { |p| p["@type"] == "http://www.w3.org/2002/07/owl#ObjectProperty" }
    assert_equal 18, opr.length
    # count datatype properties
    dpr = pr.select { |p| p["@type"] == "http://www.w3.org/2002/07/owl#DatatypeProperty" }
    assert_equal 32, dpr.length
    # count annotation properties
    apr = pr.select { |p| p["@type"] == "http://www.w3.org/2002/07/owl#AnnotationProperty" }
    assert_equal 12, apr.length
    # check for non-root properties
    assert_empty pr.select { |p| ["http://www.w3.org/2004/02/skos/core#broaderTransitive",
                                  "http://www.w3.org/2004/02/skos/core#topConceptOf",
                                  "http://www.w3.org/2004/02/skos/core#relatedMatch",
                                  "http://www.w3.org/2004/02/skos/core#exactMatch",
                                  "http://www.w3.org/2004/02/skos/core#narrowMatch"].include?(p["@id"]) },
                 "Ontology #{@@acronyms.first}: Non-root nodes found in where roots are expected"

    get "/ontologies/#{@@acronyms.last}/properties/roots"
    assert last_response.ok?
    pr = MultiJson.load(last_response.body)
    assert_equal 33, pr.length

    # count object properties
    opr = pr.select { |p| p["@type"] == "http://www.w3.org/2002/07/owl#ObjectProperty" }
    assert_equal 22, opr.length
    # count datatype properties
    dpr = pr.select { |p| p["@type"] == "http://www.w3.org/2002/07/owl#DatatypeProperty" }
    assert_equal 5, dpr.length
    # count annotation properties
    apr = pr.select { |p| p["@type"] == "http://www.w3.org/2002/07/owl#AnnotationProperty" }
    assert_equal 6, apr.length

    # check for non-root properties
    assert_empty pr.select { |p| ["http://www.semanticweb.org/ontologies/2009/9/12/Ontology1255323704656.owl#overExpress",
                                  "http://www.semanticweb.org/ontologies/2009/9/12/Ontology1255323704656.owl#underExpress"].include?(p["@id"]) },
                 "Ontology #{@@acronyms.last}: Non-root nodes found in where roots are expected"
  end

  def test_property_tree
    get "/ontologies/#{@@acronyms.first}/properties/http%3A%2F%2Fwww.w3.org%2F2004%2F02%2Fskos%2Fcore%23topConceptOf/tree"
    assert last_response.ok?
    pr = MultiJson.load(last_response.body)
    assert_equal 62, pr.length
    num_found = 0

    pr.each do |p|
      if p["@id"] == "http://www.w3.org/2004/02/skos/core#inScheme"
        num_found += 1
        assert p["hasChildren"]
        assert_equal 1, p["children"].length
        assert_equal ["is top concept in scheme"], p["children"][0]["label"]
        assert_equal true, p["hasChildren"]
        assert_empty p["children"][0]["children"]
      end

      if p["@id"] == "http://bioontology.org/ontologies/BiomedicalResourceOntology.owl#Identifier"
        num_found += 1
        assert_equal false, p["hasChildren"]
        assert_empty p["children"]
        assert_equal "http://www.w3.org/2002/07/owl#DatatypeProperty", p["@type"]
        assert_equal ["Identifier"], p["label"]
      end

      break if num_found == 2
    end

    assert_equal 2, num_found
  end

  def test_property_ancestors
    get "/ontologies/#{@@acronyms.first}/properties/http%3A%2F%2Fwww.w3.org%2F2004%2F02%2Fskos%2Fcore%23exactMatch/ancestors"
    assert last_response.ok?
    an = MultiJson.load(last_response.body)
    assert_equal 3, an.length
    assert_equal ["has close match", "is in mapping relation with", "is in semantic relation with"], an.map { |p| p["label"] }.flatten

    get "/ontologies/#{@@acronyms.last}/properties/http%3A%2F%2Fwww.semanticweb.org%2Fontologies%2F2009%2F9%2F12%2FOntology1255323704656.owl%23overExpress/ancestors"
    assert last_response.ok?
    an = MultiJson.load(last_response.body)
    assert_equal 1, an.length
    assert_equal "http://www.semanticweb.org/ontologies/2009/9/12/Ontology1255323704656.owl#express", an[0]["@id"]
  end

  def test_property_descendants
    get "/ontologies/#{@@acronyms.first}/properties/http%3A%2F%2Fwww.w3.org%2F2004%2F02%2Fskos%2Fcore%23note/descendants"
    assert last_response.ok?
    dn = MultiJson.load(last_response.body)
    assert_equal 6, dn.length
    assert_equal "http://www.w3.org/2002/07/owl#AnnotationProperty", dn[0]["@type"]
    assert_equal ["http://www.w3.org/2004/02/skos/core#historyNote",
                  "http://www.w3.org/2004/02/skos/core#example",
                  "http://www.w3.org/2004/02/skos/core#scopeNote",
                  "http://www.w3.org/2004/02/skos/core#editorialNote",
                  "http://www.w3.org/2004/02/skos/core#changeNote",
                  "http://www.w3.org/2004/02/skos/core#definition"].sort, dn.map { |d| d["@id"] }.sort

    get "/ontologies/#{@@acronyms.last}/properties/http%3A%2F%2Fwww.semanticweb.org%2Fontologies%2F2009%2F9%2F12%2FOntology1255323704656.owl%23express/descendants"
    assert last_response.ok?
    dn = MultiJson.load(last_response.body)
    assert_equal 2, dn.length
    assert_equal ["http://www.semanticweb.org/ontologies/2009/9/12/Ontology1255323704656.owl#overExpress",
                 "http://www.semanticweb.org/ontologies/2009/9/12/Ontology1255323704656.owl#underExpress"].sort, dn.map { |d| d["@id"] }.sort
  end

  def test_property_parents
    get "/ontologies/#{@@acronyms.first}/properties/http%3A%2F%2Fwww.w3.org%2F2004%2F02%2Fskos%2Fcore%23changeNote/parents"
    assert last_response.ok?
    pr = MultiJson.load(last_response.body)
    assert_equal 1, pr.length
    assert_equal "http://www.w3.org/2004/02/skos/core#note", pr[0]["@id"]

    get "/ontologies/#{@@acronyms.first}/properties/http%3A%2F%2Fwww.w3.org%2F2004%2F02%2Fskos%2Fcore%23narrowMatch/parents"
    assert last_response.ok?
    pr = MultiJson.load(last_response.body)
    assert_equal 2, pr.length
    assert_equal ["http://www.w3.org/2004/02/skos/core#mappingRelation",
                  "http://www.w3.org/2004/02/skos/core#narrower"].sort, pr.map { |p| p["@id"] }.sort

    get "/ontologies/#{@@acronyms.last}/properties/http%3A%2F%2Fwww.semanticweb.org%2Fontologies%2F2009%2F9%2F12%2FOntology1255323704656.owl%23DSMZAccessionNumber/parents"
    assert last_response.ok?
    ch = MultiJson.load(last_response.body)
    assert_empty ch
  end

  def test_property_children
    get "/ontologies/#{@@acronyms.first}/properties/http%3A%2F%2Fbioontology.org%2Fontologies%2Fbiositemap.owl%23development_stage/children"
    assert last_response.ok?
    ch = MultiJson.load(last_response.body)
    assert_empty ch

    get "/ontologies/#{@@acronyms.first}/properties/http%3A%2F%2Fwww.w3.org%2F2004%2F02%2Fskos%2Fcore%23semanticRelation/children"
    assert last_response.ok?
    ch = MultiJson.load(last_response.body)
    assert_equal 4, ch.length
    assert_equal ["http://www.w3.org/2004/02/skos/core#broaderTransitive",
                  "http://www.w3.org/2004/02/skos/core#narrowerTransitive",
                  "http://www.w3.org/2004/02/skos/core#related",
                  "http://www.w3.org/2004/02/skos/core#mappingRelation"].sort, ch.map { |c| c["@id"] }.sort

    get "/ontologies/#{@@acronyms.last}/properties/http%3A%2F%2Fwww.semanticweb.org%2Fontologies%2F2009%2F9%2F12%2FOntology1255323704656.owl%23hasMutation/children"
    assert last_response.ok?
    ch = MultiJson.load(last_response.body)
    assert_empty ch
  end

end
