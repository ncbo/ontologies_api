require_relative '../test_case'

class TestClassesController < TestCase

  def self.before_suite
    options = {ont_count: 1,
               submission_count: 3,
               submissions_to_process: [1, 2],
               process_submission: true,
               random_submission_count: false,
               process_options: {process_rdf: true, extract_metadata: false}
    }
    return LinkedData::SampleData::Ontology.create_ontologies_and_submissions(options)
  end

  def test_first_default_page
    ont = Ontology.find("TEST-ONT-0").include(:acronym).first

    submission_ids = 1..2
    submission_ids.each do |submission_id|
      call = "/ontologies/#{ont.acronym}/classes"
      call << "?ontology_submission_id=#{submission_id}" if submission_id
      get call
      assert last_response.ok?
      clss = MultiJson.load(last_response.body)
      #TODO when fixed https://github.com/ncbo/ontologies_linked_data/issues/32
      #more testing needs to be done here
      assert last_response.ok?
      assert clss["collection"].length == 50 #default size
    end
  end

  def test_include_all_should_err
    ont = Ontology.find("TEST-ONT-0").include(:acronym).first
    call = "/ontologies/#{ont.acronym}/classes?include=all"
    get call
    assert !last_response.ok?
    assert last_response.status == 422
    call = "/ontologies/#{ont.acronym}/classes/roots?include=all"
    get call
    assert !last_response.ok?
    assert last_response.status == 422

    #also descendents/ancestors are not allowed
    call = "/ontologies/#{ont.acronym}/classes/roots?include=prefLabel,descendants"
    get call
    assert !last_response.ok?
    assert last_response.status == 422
    call = "/ontologies/#{ont.acronym}/classes/roots?include=prefLabel,synonym,ancestors"
    get call
    assert !last_response.ok?
    assert last_response.status == 422
  end

  def test_notation_lookup
    ont = Ontology.find("TEST-ONT-0").include(:acronym).first
    call = "/ontologies/#{ont.acronym}/classes/BRO:0000001?include=all"
    get call
    assert last_response.ok?
    response = MultiJson.load(last_response.body)
    assert response["@id"]["Material_Resource"]
    assert response["notation"] == "BRO:0000001"

    call = "/ontologies/#{ont.acronym}/classes/BRO:0000002?include=all"
    get call
    assert last_response.ok?
    response = MultiJson.load(last_response.body)
    assert response["@id"]["People_Resource"]
    assert response["notation"] == "BRO:0000002"

    call = "/ontologies/#{ont.acronym}/classes/BRO:0000003?include=all"
    get call
    assert !last_response.ok?
    assert last_response.status == 404


    #test for notation based on prefix IRI value
    call = "/ontologies/#{ont.acronym}/classes/BRO:Ontology_Development_and_Management?include=all"
    get call
    assert last_response.ok?
    response = MultiJson.load(last_response.body)
    assert response["@id"] == "http://bioontology.org/ontologies/BiomedicalResourceOntology.owl#Ontology_Development_and_Management"
  end


  def test_all_class_pages
    ont = Ontology.find("TEST-ONT-0").include(:acronym).first

    page_response = nil
    count_terms = 0
    last_page_n = nil
    begin
      call = "/ontologies/#{ont.acronym}/classes"
      if page_response
        last_page_n = page_response['nextPage']
        call <<  "?page=#{page_response['nextPage']}"
      end
      get call
      assert last_response.ok?
      page_response = MultiJson.load(last_response.body)
      page_response["collection"].each do |item|
        assert_instance_of String, item["prefLabel"]
        assert_instance_of String, item["@id"]
        assert_instance_of Hash, item["@context"]
        assert_instance_of Hash, item["links"]
      end
      assert last_response.ok?
      count_terms = count_terms + page_response["collection"].length
    end while page_response["nextPage"]
    #bnodes thing got fixed. changed to 486.
    assert_equal 486, count_terms

    #one more page should bring no results
    call = "/ontologies/#{ont.acronym}/classes"
    call <<  "?page=#{last_page_n+1}"
    get call
    assert last_response.ok?
    page_response = MultiJson.load(last_response.body)
    assert page_response["collection"].length == 0
  end

  def test_page_include_ancestors
    ont = Ontology.find("TEST-ONT-0").include(:acronym).first
    call = "/ontologies/#{ont.acronym}/classes?include=ancestors,prefLabel"
    get call
    assert !last_response.ok?
    assert last_response.status == 422
  end

  def test_single_cls_all
    ont = Ontology.find("TEST-ONT-0").include(:acronym).first
    clss_ids = [ 'http://bioontology.org/ontologies/BiomedicalResourceOntology.owl#Molecular_Interaction',
            "http://bioontology.org/ontologies/BiomedicalResourceOntology.owl#Electron_Microscope" ]
    clss_ids.each do |cls_id|
      escaped_cls= CGI.escape(cls_id)
      call = "/ontologies/#{ont.acronym}/classes/#{escaped_cls}?include=all"
      get call
      assert last_response.ok?
      cls = MultiJson.load(last_response.body)
      assert(!cls["prefLabel"].nil?)
      assert_instance_of(String, cls["prefLabel"])
      assert_instance_of(Array, cls["synonym"])
      assert_instance_of(Hash, cls["properties"])
      assert(cls["properties"].include?("http://www.w3.org/2004/02/skos/core#prefLabel"))
    end
  end

  def test_single_cls_properties
    ont = Ontology.find("TEST-ONT-0").include(:acronym).first
    clss_ids = [ 'http://bioontology.org/ontologies/BiomedicalResourceOntology.owl#Molecular_Interaction',
            "http://bioontology.org/ontologies/BiomedicalResourceOntology.owl#Electron_Microscope" ]
    clss_ids.each do |cls_id|
      escaped_cls= CGI.escape(cls_id)
      call = "/ontologies/#{ont.acronym}/classes/#{escaped_cls}?include=properties"
      get call
      assert last_response.ok?
      cls = MultiJson.load(last_response.body)
      assert(cls["prefLabel"].nil?)
      assert_instance_of(Hash, cls["properties"])
      assert(cls["properties"].include?("http://www.w3.org/2004/02/skos/core#prefLabel"))
    end
  end

  def test_single_cls
    ont = Ontology.find("TEST-ONT-0").include(:acronym).first

    clss_ids = [ 'http://bioontology.org/ontologies/BiomedicalResourceOntology.owl#Molecular_Interaction',
            "http://bioontology.org/ontologies/BiomedicalResourceOntology.owl#Electron_Microscope" ]

    submission_ids = [nil, 1,2]
    #last submission is nil
    submission_ids.each do |submission_id|
      clss_ids.each do |cls_id|
        escaped_cls= CGI.escape(cls_id)
        call = "/ontologies/#{ont.acronym}/classes/#{escaped_cls}"
        call << "?ontology_submission_id=#{submission_id}" if submission_id
        get call
        assert last_response.ok?
        cls = MultiJson.load(last_response.body)
        assert(!cls["prefLabel"].nil?)
        assert_instance_of(String, cls["prefLabel"])
        assert_instance_of(Array, cls["synonym"])
        assert(cls["@id"] == cls_id)

        if submission_id.nil? || submission_id == 2
          assert(cls["prefLabel"]["In version 3.2"])
          assert(cls["definition"][0]["In version 3.2"])
        else
          assert(!cls["prefLabel"]["In version 3.2"])
          assert(!cls["definition"][0]["In version 3.2"])
        end

        if cls["prefLabel"].include? "Electron"
          assert_equal(1, cls["synonym"].length)
          assert_instance_of(String, cls["synonym"][0])
        else
          assert_equal(0, cls["synonym"].length)
        end
      end
    end
  end

  def test_roots_for_cls
    ont = Ontology.find("TEST-ONT-0").include(:acronym).first

    get "/ontologies/#{ont.acronym}/classes/roots?include=prefLabel,hasChildren"
    assert last_response.ok?
    roots = MultiJson.load(last_response.body)
    assert_equal 9, roots.length
    roots.each do |r|
      assert_instance_of String, r["prefLabel"]
      assert_instance_of String, r["@id"]
      assert r.include?"hasChildren"
      #By definition roots have no parents
      escaped_root_id= CGI.escape(r["@id"])
      get "/ontologies/#{ont.acronym}/classes/#{escaped_root_id}/parents"
      last_response.ok?
      parents = MultiJson.load(last_response.body)
      assert parents.length == 0
    end
  end

  def test_classes_for_not_parsed_ontology

    ont = Ontology.find("TEST-ONT-0").include(:acronym).first

    #first submission was not parsed
    get "/ontologies/#{ont.acronym}/classes/roots?ontology_submission_id=3"

    assert_equal 404, last_response.status
    assert last_response.body["has not been parsed"]
  end

  def test_tree

    ont = Ontology.find("TEST-ONT-0").include(:acronym).first

    clss_ids = [ 'http://bioontology.org/ontologies/BiomedicalResourceOntology.owl#Molecular_Interaction',
            "http://bioontology.org/ontologies/BiomedicalResourceOntology.owl#Electron_Microscope" ]
    clss_ids.each do |cls_id|
      escaped_cls= CGI.escape(cls_id)
      call = "/ontologies/#{ont.acronym}/classes/#{escaped_cls}/tree"
      get call
      tree = MultiJson.load(last_response.body)
      tree.each do |r|
        assert r.include?("hasChildren")
        assert !r.include?("childrenCount")
      end
      assert last_response.ok?
    end
  end

  def test_path_to_root_for_cls

    ont = Ontology.find("TEST-ONT-0").include(:acronym).first
    clss_ids = [ 'http://bioontology.org/ontologies/BiomedicalResourceOntology.owl#Molecular_Interaction',
            "http://bioontology.org/ontologies/BiomedicalResourceOntology.owl#Electron_Microscope" ]
    clss_ids.each do |cls_id|
      escaped_cls= CGI.escape(cls_id)
      call = "/ontologies/#{ont.acronym}/classes/#{escaped_cls}/paths_to_root"
      get call
      assert last_response.ok?
    end
  end

  def test_ancestors_for_cls

    ont = Ontology.find("TEST-ONT-0").include(:acronym).first
    ancestors_data = {}
    ancestors_data['http://bioontology.org/ontologies/BiomedicalResourceOntology.owl#Molecular_Interaction'] =[
      "http://bioontology.org/ontologies/BiomedicalResourceOntology.owl#Data_Resource",
      "http://bioontology.org/ontologies/BiomedicalResourceOntology.owl#Information_Resource",
      "http://bioontology.org/ontologies/BiomedicalResourceOntology.owl#Molecular_and_Cellular_Data",
      "http://bioontology.org/ontologies/BiomedicalResourceOntology.owl#Resource",
      ]
    ancestors_data['http://bioontology.org/ontologies/BiomedicalResourceOntology.owl#Electron_Microscope'] =[
      "http://bioontology.org/ontologies/BiomedicalResourceOntology.owl#Instrument",
      "http://bioontology.org/ontologies/BiomedicalResourceOntology.owl#Material_Resource",
      "http://bioontology.org/ontologies/BiomedicalResourceOntology.owl#Microscope",
      "http://bioontology.org/ontologies/BiomedicalResourceOntology.owl#Resource",
      ]

    clss_ids = [ 'http://bioontology.org/ontologies/BiomedicalResourceOntology.owl#Molecular_Interaction',
            "http://bioontology.org/ontologies/BiomedicalResourceOntology.owl#Electron_Microscope" ]
    clss_ids.each do |cls_id|
      escaped_cls= CGI.escape(cls_id)
      call = "/ontologies/#{ont.acronym}/classes/#{escaped_cls}/ancestors"
      get call
      assert last_response.ok?
      ancestors = MultiJson.load(last_response.body)
      ancestors.map! { |a| a["@id"] }
      assert ancestors.sort == ancestors_data[cls_id].sort
    end
  end

  def test_descendants_for_cls
    ont = Ontology.find("TEST-ONT-0").include(:acronym).first

    descendants_data = {}
    descendants_data['http://bioontology.org/ontologies/ResearchArea.owl#Area_of_Research'] =[
      "http://bioontology.org/ontologies/ResearchArea.owl#Behavioral_Science",
 "http://bioontology.org/ontologies/ResearchArea.owl#Bioinformatics",
 "http://bioontology.org/ontologies/ResearchArea.owl#Biostatistics",
 "http://bioontology.org/ontologies/ResearchArea.owl#Clinical_Studies",
 "http://bioontology.org/ontologies/ResearchArea.owl#Computational_Biology",
 "http://bioontology.org/ontologies/ResearchArea.owl#Epidemiology",
 "http://bioontology.org/ontologies/ResearchArea.owl#Genomics",
 "http://bioontology.org/ontologies/ResearchArea.owl#Metabolomics",
 "http://bioontology.org/ontologies/ResearchArea.owl#Nursing",
 "http://bioontology.org/ontologies/ResearchArea.owl#Outcomes_Research",
 "http://bioontology.org/ontologies/ResearchArea.owl#Pathology",
 "http://bioontology.org/ontologies/ResearchArea.owl#Pediatrics",
 "http://bioontology.org/ontologies/ResearchArea.owl#Pharmacokinetics_Pharmacodynamics",
 "http://bioontology.org/ontologies/ResearchArea.owl#Physiology",
 "http://bioontology.org/ontologies/ResearchArea.owl#Preclinical",
 "http://bioontology.org/ontologies/ResearchArea.owl#Proteomics",
 "http://bioontology.org/ontologies/ResearchArea.owl#Psychometrics",
 "http://bioontology.org/ontologies/ResearchArea.owl#Research_IT",
 "http://bioontology.org/ontologies/ResearchArea.owl#Toxicology"]

    descendants_data['http://bioontology.org/ontologies/Activity.owl#Activity'] =
      ["http://bioontology.org/ontologies/Activity.owl#Biospecimen_Management",
 "http://bioontology.org/ontologies/Activity.owl#Community_Engagement",
 "http://bioontology.org/ontologies/Activity.owl#Gene_Therapy",
 "http://bioontology.org/ontologies/Activity.owl#Health_Services",
 "http://bioontology.org/ontologies/Activity.owl#IRB",
 "http://bioontology.org/ontologies/Activity.owl#Medical_Device_Development",
 "http://bioontology.org/ontologies/Activity.owl#Regulatory_Compliance",
 "http://bioontology.org/ontologies/Activity.owl#Research_Funding",
 "http://bioontology.org/ontologies/Activity.owl#Research_Lab_Management",
 "http://bioontology.org/ontologies/Activity.owl#Resource_Inventory",
 "http://bioontology.org/ontologies/Activity.owl#Small_Molecule",
 "http://bioontology.org/ontologies/Activity.owl#Social_Networking",
 "http://bioontology.org/ontologies/Activity.owl#Software_Development",
 "http://bioontology.org/ontologies/Activity.owl#Surgical_Procedure",
 "http://bioontology.org/ontologies/Activity.owl#Therapeutics",
 "http://bioontology.org/ontologies/Activity.owl#Training"]

    clss_ids = [ 'http://bioontology.org/ontologies/Activity.owl#Activity',
            "http://bioontology.org/ontologies/ResearchArea.owl#Area_of_Research" ]
    clss_ids.each do |cls_id|
      escaped_cls= CGI.escape(cls_id)
      call = "/ontologies/#{ont.acronym}/classes/#{escaped_cls}/descendants"
      get call
      assert last_response.ok?
      descendants = MultiJson.load(last_response.body)
      assert descendants["page"] == 1
      descendants = descendants["collection"]
      descendants.map! { |a| a["@id"] }
      assert descendants.sort == descendants_data[cls_id].sort
    end

    #Smaller pages
    clss_ids.each do |cls_id|
      escaped_cls= CGI.escape(cls_id)
      descendants = []
      page_response = nil
      begin
        call = "/ontologies/#{ont.acronym}/classes/#{escaped_cls}/descendants?pagesize=7"
        if page_response
          call << "&page=#{page_response["nextPage"]}"
        end
        get call
        assert last_response.ok?
        page_response = MultiJson.load(last_response.body)
        descendants.concat page_response["collection"]
      end while page_response["nextPage"]
      descendants.map! { |a| a["@id"] }
      assert descendants.sort == descendants_data[cls_id].sort
    end
  end

  def test_parents_for_cls_round_trip

    clss_ids = [ 'http://bioontology.org/ontologies/BiomedicalResourceOntology.owl#Molecular_Interaction',
            "http://bioontology.org/ontologies/BiomedicalResourceOntology.owl#Electron_Microscope" ]

    parent_ids = ["http://bioontology.org/ontologies/BiomedicalResourceOntology.owl#Molecular_and_Cellular_Data",
    "http://bioontology.org/ontologies/BiomedicalResourceOntology.owl#Microscope"]

    ont = Ontology.find("TEST-ONT-0").include(:acronym).first

    clss_ids.each_index do |i|
      cls_id = clss_ids[i]
      escaped_cls= CGI.escape(cls_id)
      call = "/ontologies/#{ont.acronym}/classes/#{escaped_cls}/parents"
      get call
      assert last_response.ok?
      parents = MultiJson.load(last_response.body)
      assert parents[0]["@id"] == parent_ids[i]

      #the children of every parent must contain himself.
      parents.each do |p|
        escaped_p_id= CGI.escape(p["@id"])
        call = "/ontologies/#{ont.acronym}/classes/#{escaped_p_id}/children"
        get call
        last_response.ok?
        children = MultiJson.load(last_response.body)
        children = children["collection"]
        children.map! { |c| c["@id"] }
        assert children.length > 0 and children.include? cls_id
      end
    end
  end

  def test_parents_in_include_all
    ont = Ontology.find("TEST-ONT-0").include(:acronym).first
    cls_id = "http://bioontology.org/ontologies/BiomedicalResourceOntology.owl#Federal_Funding_Resource"
    escaped_cls= CGI.escape(cls_id)
    call = "/ontologies/#{ont.acronym}/classes/#{escaped_cls}/parents"
    get call
    assert last_response.ok?
    parents = MultiJson.load(last_response.body)
    assert parents.length == 1
    assert parents[0]["@id"]["Funding_Resource"]

    call = "/ontologies/#{ont.acronym}/classes/#{escaped_cls}?include=all"
    get call
    assert last_response.ok?
    cls_all_data = MultiJson.load(last_response.body)
    assert cls_all_data["parents"].length == 1
    assert cls_all_data["parents"][0]["@id"]["Funding_Resource"]
  end

  def test_calls_not_found
    escaped_cls= CGI.escape("http://my.bogus.inexistent.class/that/this/is")

    #404 on ontology
    get "/ontologies/NO-ONT-ZZZZZZ/classes/"
    assert last_response.status == 404
    get "/ontologies/NO-ONT-ZZZZZZ/classes/#{escaped_cls}/children"
    assert last_response.status == 404
    get "/ontologies/NO-ONT-ZZZZZZ/classes/#{escaped_cls}/parents"
    assert last_response.status == 404
    get "/ontologies/NO-ONT-ZZZZZZ/classes/#{escaped_cls}/ancestors"
    assert last_response.status == 404
    get "/ontologies/NO-ONT-ZZZZZZ/classes/#{escaped_cls}/descendants"
    assert last_response.status == 404
    get "/ontologies/NO-ONT-ZZZZZZ/classes/#{escaped_cls}"
    assert last_response.status == 404

    #404 on class id
    ont = Ontology.find("TEST-ONT-0").include(:acronym).first
    get "/ontologies/#{ont.acronym}/classes/#{escaped_cls}/children"
    assert last_response.status == 404
    get "/ontologies/#{ont.acronym}/classes/#{escaped_cls}/parents"
    assert last_response.status == 404
    get "/ontologies/#{ont.acronym}/classes/#{escaped_cls}/ancestors"
    assert last_response.status == 404
    get "/ontologies/#{ont.acronym}/classes/#{escaped_cls}/descendants"
    assert last_response.status == 404
    get "/ontologies/#{ont.acronym}/classes/#{escaped_cls}"
    assert last_response.status == 404
  end

  def test_children_for_cls_round_trip

    clss_ids = [ 'http://bioontology.org/ontologies/BiomedicalResourceOntology.owl#Molecular_and_Cellular_Data',
            "http://bioontology.org/ontologies/BiomedicalResourceOntology.owl#Microscope" ]

    children_arrays = [
      [
        "http://bioontology.org/ontologies/BiomedicalResourceOntology.owl#Gene_Expression",
        "http://bioontology.org/ontologies/BiomedicalResourceOntology.owl#Molecular_Interaction",
        "http://bioontology.org/ontologies/BiomedicalResourceOntology.owl#Phenotypic_Measurement",
        "http://bioontology.org/ontologies/BiomedicalResourceOntology.owl#Protein_Expression"
      ] , [
        "http://bioontology.org/ontologies/BiomedicalResourceOntology.owl#Electron_Microscope",
        "http://bioontology.org/ontologies/BiomedicalResourceOntology.owl#Light_Microscope"
      ] ]

    ont = Ontology.find("TEST-ONT-0").include(:acronym).first

    clss_ids.each_index do |i|
      cls_id = clss_ids[i]
      escaped_cls= CGI.escape(cls_id)
      call = "/ontologies/#{ont.acronym}/classes/#{escaped_cls}/children"
      get call
      assert last_response.ok?
      children = MultiJson.load(last_response.body)["collection"]
      #TODO eventually this should test for id and not resource_id
      children.map! { |c| c["@id"] }
      assert children.sort == children_arrays[i].sort

      #the parent of every children must contain himself.
      children.each do |c|
        escaped_c_id= CGI.escape(c)
        call = "/ontologies/#{ont.acronym}/classes/#{escaped_c_id}/parents"
        get call
        last_response.ok?
        parents = MultiJson.load(last_response.body)
        parents.map! { |p| p["@id"] }
        assert parents.length > 0 and parents.include? cls_id
      end
    end
  end

  def test_class_page_with_metric_count
    ont = Ontology.find("TEST-ONT-0").include(:acronym).first

    page_response = nil
    count_terms = 0
    last_page_n = nil
    begin
      call = "/ontologies/#{ont.acronym}/classes"
      if page_response
        last_page_n = page_response['nextPage']
        call <<  "?page=#{page_response['nextPage']}"
      end
      get call
      assert last_response.ok?
      page_response = MultiJson.load(last_response.body)
      page_response["collection"].each do |item|
        assert_instance_of String, item["prefLabel"]
        assert_instance_of String, item["@id"]
        assert_instance_of Hash, item["@context"]
        assert_instance_of Hash, item["links"]
      end
      assert last_response.ok?
      count_terms = count_terms + page_response["collection"].length
    end while page_response["nextPage"]
    #bnodes thing got fixed. changed to 486.
    assert_equal 486, count_terms

    #one more page should bring no results
    call = "/ontologies/#{ont.acronym}/classes"
    call <<  "?page=#{last_page_n+1}"
    get call
    assert last_response.ok?
    page_response = MultiJson.load(last_response.body)
    assert page_response["collection"].length == 0
  end

  def test_default_multilingual
    ont = Ontology.find("TEST-ONT-0").include(:acronym).first
    sub = ont.latest_submission
    sub.bring_remaining

    get "/ontologies/#{ont.acronym}/classes/#{CGI.escape('http://bioontology.org/ontologies/Activity.owl#Biospecimen_Management')}"
    assert last_response.ok?
    page_response = MultiJson.load(last_response.body)

    # does not contain a value in english show the generated one
    assert_equal 'Biospecimen_Management', page_response["prefLabel"]


    sub.naturalLanguage = ['fr']
    sub.save

    get "/ontologies/#{ont.acronym}/classes/#{CGI.escape('http://bioontology.org/ontologies/Activity.owl#Biospecimen_Management')}"
    assert last_response.ok?
    page_response = MultiJson.load(last_response.body)

    # show french value as specified in submission naturalLanguage
    assert_equal 'Biospecimen Management', page_response["prefLabel"]
  end
end
