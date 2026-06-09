require_relative '../test_case'

class TestSearchController < TestCase

  def before_suite
     self.backend_4s_delete
     LinkedData::Models::Ontology.indexClear
     LinkedData::Models::Class.indexClear
     LinkedData::Models::OntologyProperty.indexClear

     count, acronyms, bro = LinkedData::SampleData::Ontology.create_ontologies_and_submissions({
      process_submission: true,
      acronym: "BROSEARCHTEST",
      name: "BRO Search Test",
      file_path: "./test/data/ontology_files/BRO_v3.2.owl",
      ont_count: 1,
      submission_count: 1,
      ontology_type: "VALUE_SET_COLLECTION"
    })

    count, acronyms, mccl = LinkedData::SampleData::Ontology.create_ontologies_and_submissions({
      process_submission: true,
      acronym: "MCCLSEARCHTEST",
      name: "MCCL Search Test",
      file_path: "./test/data/ontology_files/CellLine_OWL_BioPortal_v1.0.owl",
      ont_count: 1,
      submission_count: 1
    })

    @@ontologies = bro.concat(mccl)

    @@test_user = LinkedData::Models::User.new(
        username: "test_search_user",
        email: "ncbo_search_user@example.org",
        password: "test_user_password"
    )
    @@test_user.save

    # Create a test ROOT provisional class
    @@test_pc_root = LinkedData::Models::ProvisionalClass.new({
      creator: @@test_user,
      label: "Provisional Class - ROOT",
      synonym: ["Test synonym for Prov Class ROOT", "Test syn ROOT provisional class"],
      definition: ["Test definition for Prov Class ROOT"],
      ontology: @@ontologies[0]
    })
    @@test_pc_root.save

    @@cls_uri = RDF::URI.new("http://bioontology.org/ontologies/ResearchArea.owl#Area_of_Research")
    # Create a test CHILD provisional class
    @@test_pc_child = LinkedData::Models::ProvisionalClass.new({
      creator: @@test_user,
      label: "Provisional Class - CHILD",
      synonym: ["Test synonym for Prov Class CHILD", "Test syn CHILD provisional class"],
      definition: ["Test definition for Prov Class CHILD"],
      ontology: @@ontologies[0],
      subclassOf: @@cls_uri
    })
    @@test_pc_child.save
  end

  def after_suite
    @@test_pc_root.delete
    @@test_pc_child.delete
    LinkedData::SampleData::Ontology.delete_ontologies_and_submissions
    @@test_user.delete
    LinkedData::Models::Ontology.indexClear
    LinkedData::Models::Ontology.indexCommit
  end

  def test_search
    get '/search?q=ontology'
    assert last_response.ok?

    acronyms = @@ontologies.map {|ont|
      ont.bring_remaining
      ont.acronym
    }
    results = MultiJson.load(last_response.body)

    results["collection"].each do |doc|
      acronym = doc["links"]["ontology"].split('/')[-1]
      assert acronyms.include? (acronym)
    end
  end

  def test_search_ontology_filter
    acronym = "MCCLSEARCHTEST-0"
    get "/search?q=cell%20li*&ontologies=#{acronym}"
    assert last_response.ok?
    results = MultiJson.load(last_response.body)
    doc = results["collection"][0]

    pref_label = doc["prefLabel"].kind_of?(Array) ? doc["prefLabel"].first : doc["prefLabel"]
    assert_equal "cell line", pref_label

    assert doc["links"]["ontology"].include? acronym
    results["collection"].each do |doc|
      acr = doc["links"]["ontology"].split('/')[-1]
      assert_equal acr, acronym
    end
  end

  # Phase 1 invariant: prefLabelExact and synonymExact use the string_ci
  # field type so a lowercase query matches a mixed-case stored label.
  # The schemaless-to-static migration regressed this field type to plain
  # `string`, breaking lowercase searches for terms like "melanoma" against
  # docs whose prefLabel was "Melanoma". This test exercises only the
  # schema/case-insensitive fix; the rank-ordering boost is verified
  # separately in test_search_rank_orders_results_via_solr_side_boost.
  def test_schema_uses_case_insensitive_string_ci_exact_fields
    with_ranked_melanoma_ontologies([
      ["RANKHIGH", 1.0, "./test/data/ontology_files/search_rank_melanoma_upper.owl"]
    ]) do
      schema = Goo.search_client(:term_search).fetch_schema
      pref_label_exact = schema["fields"].find { |field| field["name"] == "prefLabelExact" }
      synonym_exact = schema["fields"].find { |field| field["name"] == "synonymExact" }

      assert_equal "string_ci", pref_label_exact["type"],
                   "prefLabelExact must be string_ci so lowercase queries match mixed-case stored labels"
      assert_equal "string_ci", synonym_exact["type"],
                   "synonymExact must be string_ci for the same case-insensitive guarantee"

      # Lowercase query against RANKHIGH, whose prefLabel is "Melanoma".
      # With string_ci this returns 1; with the pre-fix plain `string` type
      # it would return 0 and the original ranking regression would surface.
      exact_match_resp = LinkedData::Models::Class.search(
        'prefLabelExact:"melanoma"',
        {
          fq: "submissionAcronym:RANKHIGH AND obsolete:false AND -provisional:true",
          fl: "submissionAcronym,prefLabel,score",
          rows: 10
        }
      )
      assert_equal 1, exact_match_resp["response"]["numFound"],
                   "lowercase 'melanoma' must match mixed-case 'Melanoma' via string_ci prefLabelExact"
    end
  end

  # Phase 2 mechanism: BioPortal ontology rank participates in Solr scoring
  # via boost=sum(ontologyRank,1) BEFORE pagination. Seeds four ontologies
  # with synthetic ranks (1.0, 0.7, 0.4, 0.1) and queries with pagesize=3.
  # Expects the three returned acronyms to be the three highest-ranked, in
  # rank order, with the lowest-ranked excluded from page 1 but still
  # counted in totalCount.
  #
  # This passes deterministically only because the Solr-side boost multiplies
  # each doc's intrinsic score by (1 + rank), producing distinct combined
  # scores (2.0x, 1.7x, 1.4x, 1.1x). Without the boost — and given that the
  # post-hoc Ruby tiebreaker has been removed — the four near-identical-score
  # docs would tie at the Solr layer and which three landed on page 1 would
  # be governed by Solr's internal tie-breaking, not by ontology rank.
  #
  # Coverage gap (deferred): with only 4 fixtures this does not exercise the
  # original issue #230 failure mode where high-rank docs are stranded beyond
  # Solr's first page (50+ matching docs would be needed to force that).
  def test_search_rank_orders_results_via_solr_side_boost
    with_ranked_melanoma_ontologies([
      ["RANKHIGH", 1.0, "./test/data/ontology_files/search_rank_melanoma_upper.owl"],
      ["RANKMIDHI", 0.7, "./test/data/ontology_files/search_rank_melanoma_lower.owl"],
      ["RANKMIDLO", 0.4, "./test/data/ontology_files/search_rank_melanoma_lower.owl"],
      ["RANKLOW", 0.1, "./test/data/ontology_files/search_rank_melanoma_lower.owl"]
    ]) do
      get "/search?q=melanoma&pagesize=3"
      assert last_response.ok?, "expected 200, got #{last_response.status}: #{last_response.body[0, 200]}"
      results = MultiJson.load(last_response.body)
      acronyms = results["collection"].map { |doc| doc["links"]["ontology"].split("/")[-1] }

      assert_operator results["totalCount"], :>=, 4,
                      "all four seeded ontologies must match q=melanoma (totalCount counts pre-pagination)"
      assert_equal 3, results["collection"].length,
                   "pagesize=3 must return exactly 3 docs on page 1"
      assert_equal %w[RANKHIGH RANKMIDHI RANKMIDLO], acronyms,
                   "Solr-side boost must order page 1 by descending ontologyRank"
      refute_includes acronyms, "RANKLOW",
                      "the lowest-ranked ontology must be excluded from page 1 even though it matches the query"
    end
  end

  # Regression: when the acronyms list filters down to empty (here via an
  # ontology_types filter that matches no seeded ontology), the Solr fq used
  # to start with " AND obsolete:false ..." — a malformed query rejected by
  # Solr (400) and surfaced as 500 by the API. Fix substitutes Solr's
  # match-all literal so the AND'd clauses concatenate cleanly.
  def test_search_with_empty_acronym_filter_returns_ok
    get "/search?q=anything&ontology_types=NONEXISTENT_TYPE"
    assert last_response.ok?, "expected 200, got #{last_response.status}: #{last_response.body[0, 200]}"
    results = MultiJson.load(last_response.body)
    assert_equal 0, results["collection"].length
  end

  def test_search_other_filters
    acronym = "MCCLSEARCHTEST-0"
    get "/search?q=receptor%20antagonists&ontologies=#{acronym}&require_exact_match=true"
    assert last_response.ok?
    results = MultiJson.load(last_response.body)
    assert_equal 1, results["collection"].length

    get "search?q=data&require_definitions=true"
    assert last_response.ok?
    results = MultiJson.load(last_response.body)
    assert results["collection"].all? {|doc| !doc["definition"].nil? && doc.values.flatten.join(" ").include?("data") }
    #assert_equal 26, results["collection"].length

    get "search?q=data&require_definitions=false"
    assert last_response.ok?
    results = MultiJson.load(last_response.body)
    assert results["collection"].length > 26

    # testing "also_search_obsolete" flag
    acronym = "BROSEARCHTEST-0"

    get "search?q=Integration%20and%20Interoperability&ontologies=#{acronym}"
    results = MultiJson.load(last_response.body)

    assert results["collection"].all? { |x| !x["obsolete"] }
    count = results["collection"].length

    get "search?q=Integration%20and%20Interoperability&ontologies=#{acronym}&also_search_obsolete=false"
    results = MultiJson.load(last_response.body)
    assert_equal count, results["collection"].length

    get "search?q=Integration%20and%20Interoperability&ontologies=#{acronym}&also_search_obsolete=true"
    results = MultiJson.load(last_response.body)
    assert_equal 29, results["collection"].length

    # testing "subtree_root_id" parameter
    get "search?q=training&ontologies=#{acronym}"
    results = MultiJson.load(last_response.body)
    assert_equal 3, results["collection"].length
    get "search?q=training&ontology=#{acronym}&subtree_root_id=http%3A%2F%2Fbioontology.org%2Fontologies%2FActivity.owl%23Activity"
    results = MultiJson.load(last_response.body)
    assert_equal 1, results["collection"].length

    # testing cui and semantic_types flags
    get "search?q=Funding%20Resource&ontologies=#{acronym}&include=prefLabel,synonym,definition,notation,cui,semanticType"
    results = MultiJson.load(last_response.body)
    #assert_equal 35, results["collection"].length
    assert results["collection"].all? do |r|
      ["prefLabel", "synonym", "definition", "notation", "cui", "semanticType"].map {|x| r[x]}
                                                                               .flatten
                                                                               .join(' ')
                                                                               .include?("Funding Resource")
    end

    label0 = results["collection"][0]["prefLabel"].kind_of?(Array) ? results["collection"][0]["prefLabel"].first : results["collection"][0]["prefLabel"]
    assert_equal "Funding Resource", label0
    assert_equal "T028", results["collection"][0]["semanticType"][0]
    assert_equal "X123456", results["collection"][0]["cui"][0]

    get "search?q=Funding&ontologies=#{acronym}&include=prefLabel,synonym,definition,notation,cui,semanticType&cui=X123456"
    results = MultiJson.load(last_response.body)
    assert_equal 1, results["collection"].length
    assert_equal "X123456", results["collection"][0]["cui"][0]

    get "search?q=Funding&ontologies=#{acronym}&include=prefLabel,synonym,definition,notation,cui,semanticType&semantic_types=T028"
    results = MultiJson.load(last_response.body)
    assert_equal 1, results["collection"].length
    assert_equal "T028", results["collection"][0]["semanticType"][0]
  end

  def test_subtree_search
    acronym = "BROSEARCHTEST-0"
    class_id = RDF::IRI.new "http://bioontology.org/ontologies/Activity.owl#Activity"
    pc1 = LinkedData::Models::ProvisionalClass.new({label: "Test Provisional Parent for Training", subclassOf: class_id, creator: @@test_user, ontology: @@ontologies[0]})
    pc1.save
    pc2 = LinkedData::Models::ProvisionalClass.new({label: "Test Provisional Leaf for Training", subclassOf: pc1.id, creator: @@test_user, ontology: @@ontologies[0]})
    pc2.save

    get "search?q=training&ontology=#{acronym}&subtree_root_id=#{CGI.escape(class_id.to_s)}"
    results = MultiJson.load(last_response.body)
    assert_equal 1, results["collection"].length

    get "search?q=training&ontology=#{acronym}&subtree_root_id=#{CGI.escape(class_id.to_s)}&also_search_provisional=true"
    results = MultiJson.load(last_response.body)
    assert_equal 3, results["collection"].length

    pc2.delete
    pc2 = LinkedData::Models::ProvisionalClass.find(pc2.id).first
    assert_nil pc2
    pc1.delete
    pc1 = LinkedData::Models::ProvisionalClass.find(pc1.id).first
    assert_nil pc1
  end

  def test_wildcard_search
    get "/search?q=lun*"
    assert last_response.ok?
    results = MultiJson.load(last_response.body)
    coll = results["collection"]
  end

  def test_search_provisional_class
    acronym = "BROSEARCHTEST-0"
    ontology_type = "VALUE_SET_COLLECTION"
    # roots only with provisional class test
    get "search?also_search_provisional=true&valueset_roots_only=true&ontology_types=#{ontology_type}&ontologies=#{acronym}"
    results = MultiJson.load(last_response.body)
    assert_equal 10, results["collection"].length
    provisional = results["collection"].select {|res| assert_equal ontology_type, res["ontologyType"]; res["provisional"]}
    assert_equal 1, provisional.length
    prov_label = provisional[0]["prefLabel"].kind_of?(Array) ? provisional[0]["prefLabel"].first : provisional[0]["prefLabel"]
    assert_equal @@test_pc_root.label, prov_label

    # subtree root with provisional class test
    get "search?ontology=#{acronym}&subtree_root_id=#{CGI::escape(@@cls_uri.to_s)}&also_search_provisional=true"
    results = MultiJson.load(last_response.body)
    assert_equal 20, results["collection"].length

    provisional = results["collection"].select {|res| res["provisional"]}
    assert_equal 1, provisional.length

    prov_label = provisional[0]["prefLabel"].kind_of?(Array) ? provisional[0]["prefLabel"].first : provisional[0]["prefLabel"]
    assert_equal @@test_pc_child.label, prov_label
  end

  def test_search_obo_id
    ncit_acronym = 'NCIT'
    ogms_acronym = 'OGMS'
    cno_acronym = 'CNO'

    begin
      LinkedData::SampleData::Ontology.create_ontologies_and_submissions({
        process_submission: true,
        acronym: ncit_acronym,
        acronym_suffix: '',
        name: "NCIT Search Test",
        pref_label_property: "http://ncicb.nci.nih.gov/xml/owl/EVS/Thesaurus.owl#P108",
        synonym_property: "http://ncicb.nci.nih.gov/xml/owl/EVS/Thesaurus.owl#P90",
        definition_property: "http://ncicb.nci.nih.gov/xml/owl/EVS/Thesaurus.owl#P97",
        file_path: "./test/data/ontology_files/ncit_test.owl",
        ontology_format: 'OWL',
        ont_count: 1,
        submission_count: 1
      })
      LinkedData::SampleData::Ontology.create_ontologies_and_submissions({
        process_submission: true,
        acronym: ogms_acronym,
        acronym_suffix: '',
        name: "OGMS Search Test",
        file_path: "./test/data/ontology_files/ogms_test.owl",
        ontology_format: 'OWL',
        ont_count: 1,
        submission_count: 1
      })
      LinkedData::SampleData::Ontology.create_ontologies_and_submissions({
        process_submission: true,
        acronym: cno_acronym,
        acronym_suffix: '',
        name: "CNO Search Test",
        file_path: "./test/data/ontology_files/CNO_05.owl",
        ontology_format: 'OWL',
        ont_count: 1,
        submission_count: 1
      })

      # mdorf, 3/2/2024, when the : is followed by a LETTER, as in NCIT:C20480,
      # then Solr does not split the query on the tokens,
      # but when the : is followed by a number, as in OGMS:0000071,
      # then Solr does split this on tokens and shows the other results
      get "/search?q=OGMS:0000071"
      assert last_response.ok?
      results = MultiJson.load(last_response.body)
      docs = results["collection"]
      assert_equal 6, docs.size
      assert_equal ogms_acronym, LinkedData::Utils::Triples.last_iri_fragment(docs[0]["links"]["ontology"])
      assert_equal cno_acronym, LinkedData::Utils::Triples.last_iri_fragment(docs[1]["links"]["ontology"])
      assert_equal ncit_acronym, LinkedData::Utils::Triples.last_iri_fragment(docs[2]["links"]["ontology"])

      label1 = docs[1]["prefLabel"].kind_of?(Array) ? docs[1]["prefLabel"].first : docs[1]["prefLabel"]
      label2 = docs[2]["prefLabel"].kind_of?(Array) ? docs[2]["prefLabel"].first : docs[2]["prefLabel"]
      label3 = docs[3]["prefLabel"].kind_of?(Array) ? docs[3]["prefLabel"].first : docs[3]["prefLabel"]
      label4 = docs[4]["prefLabel"].kind_of?(Array) ? docs[4]["prefLabel"].first : docs[4]["prefLabel"]
      label5 = docs[5]["prefLabel"].kind_of?(Array) ? docs[5]["prefLabel"].first : docs[5]["prefLabel"]

      assert_equal 'realization', label1
      assert_equal 'realization', label2
      assert label3.upcase.include?('OGMS ')
      assert label4.upcase.include?('OGMS ')
      assert label5.upcase.include?('OGMS ')

      get "/search?q=CNO:0000002"
      assert last_response.ok?
      results = MultiJson.load(last_response.body)
      docs = results["collection"]
      assert_equal 7, docs.size
      assert_equal cno_acronym, LinkedData::Utils::Triples.last_iri_fragment(docs[0]["links"]["ontology"])
      acr_1 = LinkedData::Utils::Triples.last_iri_fragment(docs[1]["links"]["ontology"])
      assert_includes [ncit_acronym, ogms_acronym], acr_1
      acr_2= LinkedData::Utils::Triples.last_iri_fragment(docs[2]["links"]["ontology"])

      assert acr_2 === ncit_acronym || acr_2 === ogms_acronym

      label3 = docs[3]["prefLabel"].kind_of?(Array) ? docs[3]["prefLabel"].first : docs[3]["prefLabel"]
      label4 = docs[4]["prefLabel"].kind_of?(Array) ? docs[4]["prefLabel"].first : docs[4]["prefLabel"]
      label5 = docs[5]["prefLabel"].kind_of?(Array) ? docs[5]["prefLabel"].first : docs[5]["prefLabel"]
      label6 = docs[6]["prefLabel"].kind_of?(Array) ? docs[6]["prefLabel"].first : docs[6]["prefLabel"]

      assert label3.upcase.include?('CNO ')
      assert label4.upcase.include?('CNO ')
      assert label5.upcase.include?('CNO ')
      assert label6.upcase.include?('CNO ')

      # mdorf, 3/2/2024, when the : is followed by a LETTER, as in NCIT:C20480,
      # then Solr does not split the query on the tokens,
      # but when the : is followed by a number, as in OGMS:0000071,
      # then Solr does split this on tokens and shows the other resuluts
      get "/search?q=Thesaurus:C20480"
      assert last_response.ok?
      results = MultiJson.load(last_response.body)
      docs = results["collection"]
      assert_equal 1, docs.size

      label0 = docs[0]["prefLabel"].kind_of?(Array) ? docs[0]["prefLabel"].first : docs[0]["prefLabel"]
      assert_equal 'Cellular Process', label0

      get "/search?q=NCIT:C20480"
      assert last_response.ok?
      results = MultiJson.load(last_response.body)
      docs = results["collection"]
      assert_equal 1, docs.size

      label0 = docs[0]["prefLabel"].kind_of?(Array) ? docs[0]["prefLabel"].first : docs[0]["prefLabel"]
      assert_equal 'Cellular Process', label0

      get "/search?q=Leukocyte Apoptotic Process&ontologies=#{ncit_acronym}"
      assert last_response.ok?
      results = MultiJson.load(last_response.body)
      docs = results["collection"]

      label0 = docs[0]["prefLabel"].kind_of?(Array) ? docs[0]["prefLabel"].first : docs[0]["prefLabel"]
      label1 = docs[1]["prefLabel"].kind_of?(Array) ? docs[1]["prefLabel"].first : docs[1]["prefLabel"]
      label2 = docs[2]["prefLabel"].kind_of?(Array) ? docs[2]["prefLabel"].first : docs[2]["prefLabel"]

      assert_equal 'Leukocyte Apoptotic Process', label0
      assert_equal 'Leukocyte Apoptotic Test Class', label1
      assert_equal 'Lymphocyte Apoptotic Process', label2
    ensure
      ont = LinkedData::Models::Ontology.find(ncit_acronym).first
      ont.delete if ont
      ont = LinkedData::Models::Ontology.find(ncit_acronym).first
      assert_nil ont

      ont = LinkedData::Models::Ontology.find(ogms_acronym).first
      ont.delete if ont
      ont = LinkedData::Models::Ontology.find(ogms_acronym).first
      assert_nil ont

      ont = LinkedData::Models::Ontology.find(cno_acronym).first
      ont.delete if ont
      ont = LinkedData::Models::Ontology.find(cno_acronym).first
      assert_nil ont
    end
  end

  def test_search_short_id
    vario_acronym = 'VARIO'

    begin
      LinkedData::SampleData::Ontology.create_ontologies_and_submissions({
        process_submission: true,
        acronym: vario_acronym,
        acronym_suffix: "",
        name: "VARIO OBO Search Test",
        file_path: "./test/data/ontology_files/vario_test.obo",
        ontology_format: 'OBO',
        ont_count: 1,
        submission_count: 1
      })
      get "/search?q=VariO:0012&ontologies=#{vario_acronym}"
      assert last_response.ok?
      results = MultiJson.load(last_response.body)
      docs = results["collection"]
      assert_equal 1, docs.size

      get "/search?q=Blah:0012&ontologies=#{vario_acronym}"
      assert last_response.ok?
      results = MultiJson.load(last_response.body)
      docs = results["collection"]
      assert_equal 0, docs.size

      get "/search?q=Vario:12345&ontologies=#{vario_acronym}"
      assert last_response.ok?
      results = MultiJson.load(last_response.body)
      docs = results["collection"]
      assert_equal 0, docs.size
    ensure
      ont = LinkedData::Models::Ontology.find(vario_acronym).first
      ont.delete if ont
      ont = LinkedData::Models::Ontology.find(vario_acronym).first
      assert ont.nil?
    end
  end

  def test_language_attribute_filter
    get "/search?q=Activit%C3%A9&ontologies=BROSEARCHTEST-0&lang=fr"
    results =  MultiJson.load(last_response.body)
    assert last_response.ok?
    assert_equal 1, results["collection"].size
    doc = results["collection"][0]
    pref_label = doc["prefLabel"].kind_of?(Array) ? doc["prefLabel"].first : doc["prefLabel"]
    assert_equal "Activité", pref_label
    assert_equal 1, doc["definition"].size
    assert 1, doc["definition"][0].include?("d’intérêt pouvant")

    get "/search?q=ActivityEnglish&ontologies=BROSEARCHTEST-0&lang=en"
    results =  MultiJson.load(last_response.body)
    assert last_response.ok?
    assert_equal 1, results["collection"].size
    doc = results["collection"][0]
    pref_label = doc["prefLabel"].kind_of?(Array) ? doc["prefLabel"].first : doc["prefLabel"]
    assert_equal "ActivityEnglish", pref_label
    assert_equal 1, doc["definition"].size
    assert 1, doc["definition"][0].include?("Activity of interest that may be related to")

    get "/search?q=ActivityEnglish&ontologies=BROSEARCHTEST-0"
    results =  MultiJson.load(last_response.body)
    assert last_response.ok?
    assert_equal 1, results["collection"].size
    doc = results["collection"][0]
    pref_label = doc["prefLabel"].kind_of?(Array) ? doc["prefLabel"].first : doc["prefLabel"]
    assert_equal "ActivityEnglish", pref_label
    assert_equal 1, doc["definition"].size
    assert 1, doc["definition"][0].include?("Activity of interest that may be related to")

    get "/search?q=Activit%C3%A9&ontologies=BROSEARCHTEST-0&lang=all"
    results =  MultiJson.load(last_response.body)
    assert last_response.ok?
    assert_equal 1, results["collection"].size
    doc = results["collection"][0]
    assert doc["prefLabel"].kind_of?(Hash)
    assert_equal 3, doc["prefLabel"].size
    assert doc["synonym"].kind_of?(Hash)
    assert_equal 1, doc["synonym"].size
    assert doc["definition"].kind_of?(Hash)
    assert_equal 2, doc["definition"].size
  end

  def test_multilingual_search
    get "/search?q=Activity&ontologies=BROSEARCHTEST-0"
    res =  MultiJson.load(last_response.body)
    refute_equal 0, res["totalCount"]

    doc = res["collection"].select{|doc| doc["@id"].to_s.eql?('http://bioontology.org/ontologies/Activity.owl#Activity')}.first
    refute_nil doc

    res = LinkedData::Models::Class.search("prefLabel_none:Activity", {:fq => "submissionAcronym:BROSEARCHTEST-0", :start => 0, :rows => 80})
    refute_equal 0, res["response"]["numFound"]
    refute_nil res["response"]["docs"].select{|doc| doc["resource_id"].eql?('http://bioontology.org/ontologies/Activity.owl#Activity')}.first

    get "/search?q=Activit%C3%A9&ontologies=BROSEARCHTEST-0&lang=fr"
    res =  MultiJson.load(last_response.body)
    refute_equal 0, res["totalCount"]
    refute_nil res["collection"].select{|doc| doc["@id"].eql?('http://bioontology.org/ontologies/Activity.owl#Activity')}.first

    get "/search?q=ActivityEnglish&ontologies=BROSEARCHTEST-0&lang=en"
    res =  MultiJson.load(last_response.body)
    refute_equal 0, res["totalCount"]
    refute_nil res["collection"].select{|doc| doc["@id"].eql?('http://bioontology.org/ontologies/Activity.owl#Activity')}.first

    get "/search?q=ActivityEnglish&ontologies=BROSEARCHTEST-0&lang=fr&require_exact_match=true"
    res =  MultiJson.load(last_response.body)
    assert_nil res["collection"].select{|doc| doc["@id"].eql?('http://bioontology.org/ontologies/Activity.owl#Activity')}.first

    get "/search?q=ActivityEnglish&ontologies=BROSEARCHTEST-0&lang=en&require_exact_match=true"
    res =  MultiJson.load(last_response.body)
    refute_nil res["collection"].select{|doc| doc["@id"].eql?('http://bioontology.org/ontologies/Activity.owl#Activity')}.first

    get "/search?q=Activity&ontologies=BROSEARCHTEST-0&lang=en&require_exact_match=true"
    res =  MultiJson.load(last_response.body)
    assert_nil res["collection"].select{|doc| doc["@id"].eql?('http://bioontology.org/ontologies/Activity.owl#Activity')}.first

    get "/search?q=Activit%C3%A9&ontologies=BROSEARCHTEST-0&lang=fr&require_exact_match=true"
    res =  MultiJson.load(last_response.body)
    refute_nil res["collection"].select{|doc| doc["@id"].eql?('http://bioontology.org/ontologies/Activity.owl#Activity')}.first
  end

  private

  # Helper for ranking-quality tests: seed BioPortal ontology rank into Redis
  # for the given ontologies, index them into the term_search Solr collection,
  # yield to the block to run assertions, then clean up Redis and ontologies.
  #
  # Each entry is [acronym, bioportal_score, owl_file_path].
  def with_ranked_melanoma_ontologies(ranked_ontologies)
    ranking = ranked_ontologies.to_h do |acronym, bioportal_score, _|
      [acronym, { bioportalScore: bioportal_score, umlsScore: 0.0 }]
    end
    rank_redis = Redis.new(host: LinkedData.settings.ontology_analytics_redis_host,
                           port: LinkedData.settings.ontology_analytics_redis_port,
                           timeout: 30)

    begin
      rank_redis.set(LinkedData::Models::Ontology::ONTOLOGY_RANK_REDIS_FIELD, Marshal.dump(ranking))

      process_options = {
        process_rdf: true,
        extract_metadata: false,
        generate_missing_labels: false,
        run_metrics: false,
        reasoning: false,
        index_search: true,
        index_properties: false
      }

      ranked_ontologies.each do |acronym, _, file_path|
        LinkedData::SampleData::Ontology.create_ontologies_and_submissions({
          process_submission: true,
          process_options: process_options,
          acronym: acronym,
          acronym_suffix: "",
          name: "#{acronym} Search Test",
          file_path: file_path,
          ont_count: 1,
          submission_count: 1
        })
      end

      yield
    ensure
      rank_redis.del(LinkedData::Models::Ontology::ONTOLOGY_RANK_REDIS_FIELD)
      ranked_ontologies.map(&:first).each do |acronym|
        ont = LinkedData::Models::Ontology.find(acronym).first
        ont.delete if ont
      end
    end
  end

end
