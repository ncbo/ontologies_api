require_relative '../test_case'

class TestMappingsController < TestCase

  def before_suite
    self.backend_4s_delete
    ["BRO-TEST-MAP-0","CNO-TEST-MAP-0","FAKE-TEST-MAP-0"].each do |acr|
      LinkedData::Models::OntologySubmission.where(ontology: [acronym: acr]).to_a.each do |s|
        s.delete
      end
      ont = LinkedData::Models::Ontology.find(acr).first
      if ont
        ont.delete
      end
    end
    LinkedData::SampleData::Ontology.create_ontologies_and_submissions({
      process_submission: true,
      acronym: "BRO-TEST-MAP",
      name: "BRO-TEST-MAP",
      file_path: "./test/data/ontology_files/BRO_v3.2.owl",
      ont_count: 1,
      submission_count: 1
    })
    LinkedData::SampleData::Ontology.create_ontologies_and_submissions({
      process_submission: true,
      acronym: "CNO-TEST-MAP",
      name: "CNO-TEST-MAP",
      file_path: "./test/data/ontology_files/CNO_05.owl",
      ont_count: 1,
      submission_count: 1
    })
    LinkedData::SampleData::Ontology.create_ontologies_and_submissions({
      process_submission: true,
      acronym: "FAKE-TEST-MAP",
      name: "FAKE-TEST-MAP",
      file_path: "./test/data/ontology_files/fake_for_mappings.owl",
      ont_count: 1,
      submission_count: 1
    })
    NcboCron::Models::QueryWarmer.new(Logger.new(TestLogFile.new)).run
  end

  def test_mappings_controllers_in_order
    LinkedData::Mappings.create_mapping_counts(Logger.new(TestLogFile.new))
    mappings_between_ontologies
    mappings_for_ontology
    mappings_for_ontology_pages
    mappings_with_display
    mappings_root
    get_single_mapping
    create_mapping
    delete_mapping
    mappings_statistics
    mappings_statistics_for_ontology
  end

  def mappings_for_ontology
    LinkedData::Models::RestBackupMapping.all.each do |m|
      LinkedData::Mappings.delete_rest_mapping(m.id)
    end
    ontology = "BRO-TEST-MAP-0"
    get "/ontologies/#{ontology}/mappings"
    assert last_response.ok?
    mappings = MultiJson.load(last_response.body)

    #pages
    assert mappings["page"] == 1
    assert mappings["pageCount"] == 1
    assert mappings["prevPage"] == nil
    assert mappings["nextPage"] == nil

    assert_equal 18, mappings["collection"].length
    mappings = mappings["collection"]

    mappings.each do |mapping|
      assert mapping["classes"].length, 2
      assert mapping["source"] != nil
      assert mapping["source"].length > 0
      origin = nil
      mapping["classes"].each do |c|
        assert c["@type"]["owl#Class"] != nil
        assert c["links"] != nil
        assert c["links"]["ontology"] != nil
        if c["links"]["ontology"][ontology] != nil
          origin = c["@id"]
        end
      end
      #Linked data already tests for correct mappings
      #in API we just need to test for the data structure
      assert origin != nil
    end
  end

  def mappings_between_ontologies
    LinkedData::Models::RestBackupMapping.all.each do |m|
      LinkedData::Mappings.delete_rest_mapping(m.id)
    end
    bro_uri = LinkedData::Models::Ontology.find("BRO-TEST-MAP-0").first.id.to_s
    fake_uri = LinkedData::Models::Ontology.find("FAKE-TEST-MAP-0").first.id.to_s
    ontologies_params = [
      "BRO-TEST-MAP-0,FAKE-TEST-MAP-0",
      "#{bro_uri},#{fake_uri}",
    ]
    ontologies_params.each do |ontologies|
      ont1, ont2 = ontologies.split(",")
      get "/mappings/?ontologies=#{ontologies}"
      assert last_response.ok?
      mappings = MultiJson.load(last_response.body)
      #pages
      assert mappings["page"] == 1
      assert mappings["pageCount"] == 1
      assert mappings["prevPage"] == nil
      assert mappings["nextPage"] == nil

      assert_equal 8, mappings["collection"].length
      mappings = mappings["collection"]
      mappings.each do |mapping|
        assert mapping["classes"].length, 2
        mapping["classes"].each do |c|
          assert c["@type"]["owl#Class"] != nil
          assert c["links"] != nil
          assert c["links"]["ontology"] != nil

          class_ont = c["links"]["ontology"]
          assert class_ont[ont1] != nil || class_ont[ont2] != nil
        end
      end
    end
  end

  def mappings_for_ontology_pages
    LinkedData::Models::RestBackupMapping.all.each do |m|
      LinkedData::Mappings.delete_rest_mapping(m.id)
    end
    ontology = "BRO-TEST-MAP-0"
    pagesize = 4
    page = 1
    next_page = nil
    total = 0
    begin
      get "/ontologies/#{ontology}/mappings?pagesize=#{pagesize}&page=#{page}"
      assert last_response.ok?
      mappings = MultiJson.load(last_response.body)
      #pages
      assert_equal page, mappings["page"]
      assert_equal 5, mappings["pageCount"]
      assert mappings["prevPage"] == (page > 1 ? page - 1 : nil)
      assert mappings["nextPage"] == (page < 5 ? page + 1 : nil)
      next_page = mappings["nextPage"]
      mappings = mappings["collection"]
      total += mappings.length
      page = next_page
    end while (next_page)
    assert_equal 18, total
  end

  def mappings_with_display
    ontology = "BRO-TEST-MAP-0"
    pagesize = 4
    page = 1
    next_page = nil
    get "/ontologies/#{ontology}/mappings?pagesize=#{pagesize}&page=#{page}&display=prefLabel"
    assert last_response.ok?
    mappings = MultiJson.load(last_response.body)
    assert mappings["collection"].all? {|m| m["classes"].all? {|c| c["prefLabel"].is_a?(String) && c["prefLabel"].length > 0} }

    def_count = 0
    next_page = 1
    begin
      get "/ontologies/#{ontology}/mappings?pagesize=#{pagesize}&page=#{next_page}&display=prefLabel,definition"
      assert last_response.ok?
      mappings = MultiJson.load(last_response.body)
      def_count += mappings["collection"].map {|m| m["classes"].map {|c| (c["definition"] || []).length }}.flatten.sum
      next_page = mappings["nextPage"]
    end while (next_page)
    assert 10, def_count
  end

  def mappings_root
    #not supported
    get '/mappings'
    assert !last_response.ok?
  end

  def get_single_mapping
    #not supported
    get "/mappings/some_fake_id"
    assert !last_response.ok?
  end

  def create_mapping
    LinkedData::Models::RestBackupMapping.all.each do |m|
      LinkedData::Mappings.delete_rest_mapping(m.id)
    end

    mapping_term_a = ["http://bioontology.org/ontologies/BiomedicalResourceOntology.owl#Image_Algorithm",
      "http://bioontology.org/ontologies/BiomedicalResourceOntology.owl#Image",
      "http://bioontology.org/ontologies/BiomedicalResourceOntology.owl#Integration_and_Interoperability_Tools" ]
    mapping_ont_a = ["BRO-TEST-MAP-0","BRO-TEST-MAP-0","BRO-TEST-MAP-0"]


    mapping_term_b = ["http://purl.org/incf/ontology/Computational_Neurosciences/cno_alpha.owl#cno_0000202",
      "http://purl.org/incf/ontology/Computational_Neurosciences/cno_alpha.owl#cno_0000203",
      "http://purl.org/incf/ontology/Computational_Neurosciences/cno_alpha.owl#cno_0000205" ]
    mapping_ont_b = ["CNO-TEST-MAP-0","CNO-TEST-MAP-0","CNO-TEST-MAP-0"]

    relations = [ "http://www.w3.org/2004/02/skos/core#exactMatch",
                  "http://www.w3.org/2004/02/skos/core#closeMatch",
                  "http://www.w3.org/2004/02/skos/core#relatedMatch" ]

    3.times do |i|
      classes = {}
      classes[mapping_term_a[i]] = mapping_ont_a[i]
      classes[mapping_term_b[i]] = mapping_ont_b[i]

      mapping = { classes: classes,
                  comment: "comment for mapping test #{i}",
                  relation: relations[i],
                  creator: "http://data.bioontology.org/users/tim"
      }

      post "/mappings/",
            MultiJson.dump(mapping),
            "CONTENT_TYPE" => "application/json"

      assert last_response.status == 201
      response = MultiJson.load(last_response.body)
      assert response["process"]["comment"] == "comment for mapping test #{i}"
      assert response["process"]["creator"]["users/tim"]
      assert response["process"]["relation"] == relations[i]
      assert response["process"]["date"] != nil
      response["classes"].each do |cls|
        if cls["links"]["ontology"].split("/")[-1] == mapping_ont_a[i]
          assert cls["@id"] == mapping_term_a[i]
        elsif cls["links"]["ontology"].split("/")[-1] == mapping_ont_b[i]
          assert cls["@id"] == mapping_term_b[i]
        else
          assert 1==0, "uncontrolled mapping response in post"
        end
      end
      # to ensure different in times in dates. Later test on recent mappings
      sleep(1.2)
    end

    #there three mappings in BRO with processes
    NcboCron::Models::QueryWarmer.new(Logger.new(TestLogFile.new)).run
    ontology = "BRO-TEST-MAP-0"
    get "/ontologies/#{ontology}/mappings?pagesize=1000&page=1"
    assert last_response.ok?
    mappings = MultiJson.load(last_response.body)
    mappings = mappings["collection"]
    assert mappings.length == 21
    rest_count = 0
    mappings.each do |x|
      if x["process"] != nil
        rest_count += 1
        #assert x["@id"] != nil
      end
    end
    assert rest_count == 3

    get "/mappings/recent/"
    assert last_response.status == 200
    response = MultiJson.load(last_response.body)
    assert (response.length == 5)
    date = nil
    response.each do |x|
      assert x["@id"] != nil
      assert x["classes"].length == 2
      assert x["process"] != nil
      date_x = DateTime.iso8601(x["process"]["date"])
      if date
        assert date >= date_x
      end
      date = date_x
    end
  end

  def delete_mapping
    LinkedData::Models::RestBackupMapping.all.each do |m|
      LinkedData::Mappings.delete_rest_mapping(m.id)
    end
    assert LinkedData::Models::RestBackupMapping.all.count == 0
    rest_predicate = LinkedData::Mappings.mapping_predicates()["REST"][0]
    epr = Goo.sparql_query_client(:main)
    epr.query("SELECT (count(?s) as ?c) WHERE { ?s <#{rest_predicate}> ?o . }")
          .each do |sol|
      assert sol[:c].object == 0
    end

    mapping_term_a = ["http://bioontology.org/ontologies/BiomedicalResourceOntology.owl#Image_Algorithm",
      "http://bioontology.org/ontologies/BiomedicalResourceOntology.owl#Image",
      "http://bioontology.org/ontologies/BiomedicalResourceOntology.owl#Integration_and_Interoperability_Tools" ]
    mapping_ont_a = ["BRO-TEST-MAP-0","BRO-TEST-MAP-0","BRO-TEST-MAP-0"]


    mapping_term_b = ["http://purl.org/incf/ontology/Computational_Neurosciences/cno_alpha.owl#cno_0000202",
      "http://purl.org/incf/ontology/Computational_Neurosciences/cno_alpha.owl#cno_0000203",
      "http://purl.org/incf/ontology/Computational_Neurosciences/cno_alpha.owl#cno_0000205" ]
    mapping_ont_b = ["CNO-TEST-MAP-0","CNO-TEST-MAP-0","CNO-TEST-MAP-0"]

    relations = [ "http://www.w3.org/2004/02/skos/core#exactMatch",
                  "http://www.w3.org/2004/02/skos/core#closeMatch",
                  "http://www.w3.org/2004/02/skos/core#relatedMatch" ]

    3.times do |i|
      classes = {}
      classes[mapping_term_a[i]] = mapping_ont_a[i]
      classes[mapping_term_b[i]] = mapping_ont_b[i]

      mapping = { classes: classes,
                  comment: "comment for mapping test #{i}",
                  relation: relations[i],
                  creator: "http://data.bioontology.org/users/tim"
      }

      post "/mappings/",
            MultiJson.dump(mapping),
            "CONTENT_TYPE" => "application/json"

      assert last_response.status == 201
      response = MultiJson.load(last_response.body)
      assert response["process"]["comment"] == "comment for mapping test #{i}"
      assert response["process"]["creator"]["users/tim"]
      assert response["process"]["relation"] == relations[i]
      assert response["process"]["date"] != nil
      response["classes"].each do |cls|
        if cls["links"]["ontology"].split("/")[-1] == mapping_ont_a[i]
          assert cls["@id"] == mapping_term_a[i]
        elsif cls["links"]["ontology"].split("/")[-1] == mapping_ont_b[i]
          assert cls["@id"] == mapping_term_b[i]
        else
          assert 1==0, "uncontrolled mapping response in post"
        end
      end
      sleep(1.2) # to ensure different in times in dates. Later test on recent mappings
    end

    LinkedData::Models::RestBackupMapping.all.each do |m|
      m_id = CGI.escape(m.id.to_s)
      get "/mappings/#{m_id}"
      assert last_response.status == 200
      mapping = MultiJson.load(last_response.body)
      assert mapping["classes"].length == 2
      assert mapping["process"] != nil
      delete "/mappings/#{m_id}"
      assert last_response.status == 204
      get "/mappings/#{m_id}"
      assert last_response.status == 404
    end
    assert LinkedData::Models::RestBackupMapping.all.count == 0

    epr = Goo.sparql_query_client(:main)
    epr.query("SELECT (count(?s) as ?c) WHERE { ?s <#{rest_predicate}> ?o . }")
          .each do |sol|
      assert sol[:c].object == 0
    end
  end

  def mappings_statistics
    LinkedData::Models::RestBackupMapping.all.each do |m|
      LinkedData::Mappings.delete_rest_mapping(m.id)
    end
    NcboCron::Models::QueryWarmer.new(Logger.new(TestLogFile.new)).run
    assert LinkedData::Models::MappingCount.where.all.length > 2
    get "/mappings/statistics/ontologies/"
    assert last_response.ok?
    stats = MultiJson.load(last_response.body)
    data = {"BRO-TEST-MAP-0"=>18,
            "CNO-TEST-MAP-0"=>19,
            "FAKE-TEST-MAP-0"=>17}
    assert_equal data, stats
  end

  def mappings_statistics_for_ontology
    LinkedData::Models::RestBackupMapping.all.each do |m|
      LinkedData::Mappings.delete_rest_mapping(m.id)
    end
    NcboCron::Models::QueryWarmer.new(Logger.new(TestLogFile.new)).run
    assert LinkedData::Models::MappingCount.where.all.length > 2
    ontology = "BRO-TEST-MAP-0"
    get "/mappings/statistics/ontologies/#{ontology}"
    assert last_response.ok?
    stats = MultiJson.load(last_response.body)
    assert_equal 10, stats["CNO-TEST-MAP-0"]
    assert_equal 8, stats["FAKE-TEST-MAP-0"]
    ontology = "FAKE-TEST-MAP-0"
    get "/mappings/statistics/ontologies/#{ontology}"
    assert last_response.ok?
    stats = MultiJson.load(last_response.body)
    assert_equal 8, stats["BRO-TEST-MAP-0"]
    assert_equal 9, stats["CNO-TEST-MAP-0"]
  end

end
