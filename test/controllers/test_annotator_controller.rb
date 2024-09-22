require_relative '../test_case'

class TestAnnotatorController < TestCase

  def self.before_suite
    @@redis = Redis.new(:host => Annotator.settings.annotator_redis_host, :port => Annotator.settings.annotator_redis_port)
    db_size = @@redis.dbsize
    if db_size > MAX_TEST_REDIS_SIZE
      puts "   This test cannot be run because there #{db_size} redis entries (max #{MAX_TEST_REDIS_SIZE}). You are probably pointing to the wrong redis backend. "
      return
    end

    mappings = @@redis.keys.select { |x| x["mappings:"] }
    if mappings.length > 0
      @@redis.del(mappings)
    end

    LinkedData::SampleData::Ontology.delete_ontologies_and_submissions
    @@ontologies = LinkedData::SampleData::Ontology.sample_owl_ontologies(process_submission: true,
                                                                          process_options: {
                                                                            process_rdf: true,
                                                                            extract_metadata: false,
                                                                            index_search: true
                                                                          })
    annotator = Annotator::Models::NcboAnnotator.new
    annotator.init_redis_for_tests()
    annotator.create_term_cache_from_ontologies(@@ontologies, false)
    mapping_test_set
  end

  def test_annotate
    text = <<eos
Ginsenosides chemistry, biosynthesis, analysis, and potential health effects in software concept or data." "Ginsenosides are a special group of triterpenoid saponins that can be classified into two groups by the skeleton of their aglycones, namely dammarane- and oleanane-type. Ginsenosides are found nearly exclusively in Panax species (ginseng) and up to now more than 150 naturally occurring ginsenosides have been isolated from roots, leaves/stems, fruits, and/or flower heads of ginseng. The same concept indicates Ginsenosides have been the target of a lot of research as they are believed to be the main active principles behind the claims of ginsengs efficacy. The potential health effects of ginsenosides that are discussed in this chapter include anticarcinogenic, immunomodulatory, anti-inflammatory, antiallergic, antiatherosclerotic, antihypertensive, and antidiabetic effects as well as antistress activity and effects on the central nervous system. Ginsensoides can be metabolized in the stomach (acid hydrolysis) and in the gastrointestinal tract (bacterial hydrolysis) or transformed to other ginsenosides by drying and steaming of ginseng to more bioavailable and bioactive ginsenosides. The metabolization and transformation of intact ginsenosides, which seems to play an important role for their potential health effects, are discussed. Qualitative and quantitative analytical techniques for the analysis of ginsenosides are important in relation to quality control of ginseng products and plant material and for the determination of the effects of processing of plant material as well as for the determination of the metabolism and bioavailability of ginsenosides. Analytical techniques for the analysis of ginsenosides that are described in this chapter are thin-layer chromatography (TLC), high-performance liquid chromatography (HPLC) combined with various detectors, gas chromatography (GC), colorimetry, enzyme immunoassays (EIA), capillary electrophoresis (CE), nuclear magnetic resonance (NMR) spectroscopy, and spectrophotometric methods.
eos
    params = {text: text}
    get "/annotator", params
    assert last_response.ok?
    annotations = MultiJson.load(last_response.body)
    assert_equal(7, annotations.length)

    text = <<eos
Aggregate Human Data chromosomal mutation Aggregate Human Data chromosomal deletion Aggregate Human Data Resource Federal Funding Resource receptor antagonists chromosomal mutation.
eos
    params[:text] = text
    get "/annotator", params
    annotations = MultiJson.load(last_response.body)
    assert_equal(9, annotations.length)

    #testing "exclude_synonyms" parameter
    text = "This project requires a massive data repository, capable of storing hundreds of terabytes of information."
    params[:text] = text
    get "/annotator", params
    annotations = MultiJson.load(last_response.body)
    assert_equal(2, annotations.length)

    params[:exclude_synonyms] = "true"
    get "/annotator", params
    annotations = MultiJson.load(last_response.body)
    assert_equal(1, annotations.length)

    # test for "with_synonyms"
    params = {text: text, with_synonyms: "false"}
    get "/annotator", params
    annotations = MultiJson.load(last_response.body)
    assert_equal(1, annotations.length)
  end

  def test_annotate_hierarchy
    text = "Aggregate Human Data chromosomal mutation Aggregate Human Data chromosomal deletion Aggregate Human Data Resource Federal Funding Resource receptor antagonists chromosomal mutation"

    params = {text: text, expand_class_hierarchy: "true", class_hierarchy_max_level: 5}
    get "/annotator", params
    assert last_response.ok?
    annotations = MultiJson.load(last_response.body)

    assert annotations.length == 9

    assert annotations[0]["annotatedClass"]["@id"] == "http://bioontology.org/ontologies/BiomedicalResourceOntology.owl#Aggregate_Human_Data"
    hhh = annotations[0]["hierarchy"].sort_by {|x| x["distance"]}.map { |x| x["annotatedClass"]["@id"] }
    assert hhh == ["http://bioontology.org/ontologies/BiomedicalResourceOntology.owl#Clinical_Care_Data",
                   "http://bioontology.org/ontologies/BiomedicalResourceOntology.owl#Data_Resource",
                   "http://bioontology.org/ontologies/BiomedicalResourceOntology.owl#Information_Resource",
                   "http://bioontology.org/ontologies/BiomedicalResourceOntology.owl#Resource"]

    assert annotations[1]["annotatedClass"]["@id"] == "http://purl.obolibrary.org/obo/MCBCC_0000288#ChromosomalMutation"
    hhh = annotations[1]["hierarchy"].sort_by {|x| x["distance"]}.map { |x| x["annotatedClass"]["@id"] }
    assert hhh == ["http://purl.obolibrary.org/obo/MCBCC_0000287#GeneticVariation"]

    assert annotations[2]["annotatedClass"]["@id"] == "http://purl.obolibrary.org/obo/MCBCC_0000289#ChromosomalDeletion"
    hhh = annotations[2]["hierarchy"].sort_by {|x| x["distance"]}.map { |x| x["annotatedClass"]["@id"] }
    assert hhh == ["http://purl.obolibrary.org/obo/MCBCC_0000288#ChromosomalMutation",
                  "http://purl.obolibrary.org/obo/MCBCC_0000287#GeneticVariation"]

    assert annotations[3]["annotatedClass"]["@id"] == "http://purl.obolibrary.org/obo/MCBCC_0000296#Deletion"
    hhh = annotations[3]["hierarchy"].sort_by {|x| x["distance"]}.map { |x| x["annotatedClass"]["@id"] }
    assert hhh == ["http://purl.obolibrary.org/obo/MCBCC_0000295#GeneMutation",
                   "http://purl.obolibrary.org/obo/MCBCC_0000287#GeneticVariation"]

    assert annotations[4]["annotatedClass"]["@id"] == "http://bioontology.org/ontologies/BiomedicalResourceOntology.owl#Data_Resource"
    hhh = annotations[4]["hierarchy"].sort_by {|x| x["distance"]}.map { |x| x["annotatedClass"]["@id"] }
    assert hhh == ["http://bioontology.org/ontologies/BiomedicalResourceOntology.owl#Information_Resource",
                   "http://bioontology.org/ontologies/BiomedicalResourceOntology.owl#Resource"]

    assert annotations[5]["annotatedClass"]["@id"] == "http://bioontology.org/ontologies/BiomedicalResourceOntology.owl#Resource"
    hhh = annotations[5]["hierarchy"].sort_by {|x| x["distance"]}.map { |x| x["annotatedClass"]["@id"] }
    assert hhh == []

    assert annotations[6]["annotatedClass"]["@id"] == "http://bioontology.org/ontologies/BiomedicalResourceOntology.owl#Federal_Funding_Resource"
    hhh = annotations[6]["hierarchy"].sort_by {|x| x["distance"]}.map { |x| x["annotatedClass"]["@id"] }
    assert hhh == ["http://bioontology.org/ontologies/BiomedicalResourceOntology.owl#Funding_Resource",
                   "http://bioontology.org/ontologies/BiomedicalResourceOntology.owl#Resource"]

    assert annotations[7]["annotatedClass"]["@id"] == "http://bioontology.org/ontologies/BiomedicalResourceOntology.owl#Funding_Resource"
    hhh = annotations[7]["hierarchy"].sort_by {|x| x["distance"]}.map { |x| x["annotatedClass"]["@id"] }
    assert hhh == ["http://bioontology.org/ontologies/BiomedicalResourceOntology.owl#Resource"]

    assert annotations[8]["annotatedClass"]["@id"] == "http://purl.obolibrary.org/obo/MCBCC_0000275#ReceptorAntagonists"
    hhh = annotations[8]["hierarchy"].sort_by {|x| x["distance"]}.map { |x| x["annotatedClass"]["@id"] }
    assert hhh == ["http://purl.obolibrary.org/obo/MCBCC_0000256#ChemicalsAndDrugs"]
  end

  def test_annotate_with_mappings
    text = "Aggregate Human Data chromosomal mutation Aggregate Human Data chromosomal deletion Aggregate Human Data Resource Federal Funding Resource receptor antagonists chromosomal mutation"

    params = {text: text, expand_mappings: "true"}
    get "/annotator", params
    assert last_response.ok?
    annotations = MultiJson.load(last_response.body)

    step_in_here = 0
    annotations.each do |ann|
      if ann["annotatedClass"]["@id"] ==
          "http://bioontology.org/ontologies/BiomedicalResourceOntology.owl#Aggregate_Human_Data"
        step_in_here += 1
        assert ann["mappings"].length == 1
        assert ann["mappings"].first["annotatedClass"]["@id"] ==
            "http://www.semanticweb.org/associatedmedicine/lavima/2011/10/Ontology1.owl#Article"
        assert ann["mappings"].first["annotatedClass"]["links"]["ontology"]["ONTOMATEST-0"]
      elsif ann["annotatedClass"]["@id"] ==
          "http://bioontology.org/ontologies/BiomedicalResourceOntology.owl#Data_Resource"
        step_in_here += 1
        assert ann["mappings"].length == 2
        ann["mappings"].each do |map|
          if map["annotatedClass"]["@id"] =="http://www.semanticweb.org/associatedmedicine/lavima/2011/10/Ontology1.owl#Maux_de_rein"
            assert map["annotatedClass"]["links"]["ontology"]["ONTOMATEST-0"]
          elsif map["annotatedClass"]["@id"] == "http://purl.obolibrary.org/obo/MCBCC_0000344#PapillaryInvasiveDuctalTumor"
            assert map["annotatedClass"]["links"]["ontology"]["MCCLTEST-0"]
          else
            assert 1==0
          end
        end
      else
        ann["mappings"].length == 0
      end
    end
    assert step_in_here == 2

  end

  def test_annotate_mappings_with_ontologies

    text = "Aggregate Human Data chromosomal mutation Aggregate Human Data chromosomal deletion Aggregate Human Data Resource Federal Funding Resource receptor antagonists chromosomal mutation"

    ontologies = "http://data.bioontology.org/ontologies/ONTOMATEST-0," +
                 "http://data.bioontology.org/ontologies/BROTEST-0"
    params = {text: text, expand_mappings: "true", ontologies: ontologies}
    get "/annotator", params
    assert last_response.ok?
    annotations = MultiJson.load(last_response.body)

    step_in_here = 0
    annotations.each do |ann|
      if ann["annotatedClass"]["@id"] ==
          "http://bioontology.org/ontologies/BiomedicalResourceOntology.owl#Aggregate_Human_Data"
        step_in_here += 1
        assert ann["mappings"].length == 1
        assert ann["mappings"].first["annotatedClass"]["@id"] ==
            "http://www.semanticweb.org/associatedmedicine/lavima/2011/10/Ontology1.owl#Article"
        assert ann["mappings"].first["annotatedClass"]["links"]["ontology"]["ONTOMATEST-0"]
      elsif ann["annotatedClass"]["@id"] ==
          "http://bioontology.org/ontologies/BiomedicalResourceOntology.owl#Data_Resource"
        step_in_here += 1
        assert ann["mappings"].length == 1
        ann["mappings"].each do |map|
          if map["annotatedClass"]["@id"] =="http://www.semanticweb.org/associatedmedicine/lavima/2011/10/Ontology1.owl#Maux_de_rein"
            assert map["annotatedClass"]["links"]["ontology"]["ONTOMATEST-0"]
          else
            assert 1==0
          end
        end
      else
        assert ann["annotatedClass"]["links"]["ontology"]["BROTEST-0"] ||
               ann["annotatedClass"]["links"]["ontology"]["ONTOMATEST-0"]
        ann["mappings"].length == 0
      end
    end
    assert step_in_here == 2
  end

  def test_long_annotation_post
    classes = TestAnnotatorController.all_classes(@@ontologies)
    classes = classes[0..500]
    text = []
    classes.each do |cls|
      text << cls.prefLabel
    end
    text = text.join(" ")

    params = { text: text }
    post "/annotator", params
    assert last_response.ok?
    annotations = MultiJson.load(last_response.body)
    classes.each do |cls|
      if cls.prefLabel.length > 2
        annotations.map { |x| x["annotatedClass"]["@id"] == cls.id.to_s }.length > 0
      end
    end
    assert annotations.length >= classes.length
  end

  def test_stop_words
    text = "Resource Aggregate Human Data deletion"
    params = { text: text }
    post "/annotator", params
    assert last_response.ok?
    annotations = MultiJson.load(last_response.body)
    assert annotations.length == 3
    params = { text: text , stop_words: ["resOUrce", "DeletioN"]}
    post "/annotator", params
    annotations = MultiJson.load(last_response.body)
    assert annotations.length == 1
    assert annotations.first["annotatedClass"]["@id"] ==
      "http://bioontology.org/ontologies/BiomedicalResourceOntology.owl#Aggregate_Human_Data"
  end

  def test_minterm_size
    classes = TestAnnotatorController.all_classes(@@ontologies)
    classes = classes[0..500]
    text = []
    not_show = []
    classes.each do |cls|
      text << cls.prefLabel
      if (cls.prefLabel.length < 10 && cls.prefLabel.length > 2)
        not_show << cls
      end
    end
    text = text.join(" ")
    assert not_show.length > 0

    params = { text: text , minTermSize: 10}
    post "/annotator", params
    assert last_response.ok?
    annotations = MultiJson.load(last_response.body)
    not_show.each do |cls|
      annotations.map { |x| x["annotatedClass"]["@id"] == cls }.length == 0
    end
    assert annotations.length > 0
  end

  def test_default_properties_output
    text = "Aggregate Human Data chromosomal mutation Aggregate Human Data chromosomal deletion Aggregate Human Data Resource Federal Funding Resource receptor antagonists chromosomal mutation"

    params = {text: text, include: "prefLabel"}
    get "/annotator", params
    assert last_response.ok?
    annotations = MultiJson.load(last_response.body)
    assert_equal 9, annotations.length
    annotations.sort! { |a,b| a["annotatedClass"]["prefLabel"].first.downcase <=> b["annotatedClass"]["prefLabel"].first.downcase }
    assert_equal "http://bioontology.org/ontologies/BiomedicalResourceOntology.owl#Aggregate_Human_Data", annotations.first["annotatedClass"]["@id"]
    assert_equal "Aggregate Human Data", annotations.first["annotatedClass"]["prefLabel"]

    params = {text: text, include: "prefLabel,definition"}
    get "/annotator", params
    assert last_response.ok?
    annotations = MultiJson.load(last_response.body)
    assert_equal 9, annotations.length
    annotations.sort! { |a,b| a["annotatedClass"]["prefLabel"].downcase <=> b["annotatedClass"]["prefLabel"].downcase }
    assert_equal "http://bioontology.org/ontologies/BiomedicalResourceOntology.owl#Aggregate_Human_Data", annotations.first["annotatedClass"]["@id"]
    assert_equal ["A resource that provides data from clinical care that comprises combined data from multiple individual human subjects."], annotations.first["annotatedClass"]["definition"]
  end

  def test_recognizer_endpoint
    recognizers = []
    ObjectSpace.each_object(Annotator::Models::NcboAnnotator.singleton_class).each do |c|
      next if c == Annotator::Models::NcboAnnotator
      recognizer = c.name.downcase.split("::").last
      recognizers << recognizer.to_sym
    end
    get "/annotator/recognizers"
    assert last_response.ok?
    rest_recognizers = MultiJson.load(last_response.body)
    assert rest_recognizers.length > 0

    default_rec_setting = Annotator.settings.supported_recognizers
    Annotator.settings.supported_recognizers = recognizers

    get "/annotator/recognizers"
    assert last_response.ok?
    rest_recognizers = MultiJson.load(last_response.body)
    assert rest_recognizers.length > 0
    assert_equal recognizers.length, rest_recognizers.length
    assert_equal recognizers.sort, rest_recognizers.map {|r| r.to_sym}.sort
  end

  #TODO: this method is duplicated in NCBO_ANNOTATOR
  def self.all_classes(ontologies)
    classes = []
    ontologies.each do |ontology|
      last = ontology.latest_submission
      page = 1
      size = 500
      paging = LinkedData::Models::Class.in(last)
                            .include(:prefLabel, :synonym, :definition)
                            .page(page, size)
      begin
        page_classes = paging.page(page,size).all
        page = page_classes.next? ? page + 1 : nil
        classes += page_classes
      end while !page.nil?
    end
    return classes
  end

  #TODO: this method is duplicated in NCBO_ANNOTATOR
  def self.mapping_test_set
    Goo.sparql_data_client.delete_graph(LinkedData::Models::MappingProcess.type_uri)
    terms_a = ["http://bioontology.org/ontologies/BiomedicalResourceOntology.owl#Resource",
               "http://bioontology.org/ontologies/BiomedicalResourceOntology.owl#Aggregate_Human_Data",
               "http://bioontology.org/ontologies/BiomedicalResourceOntology.owl#Data_Resource",
               "http://bioontology.org/ontologies/BiomedicalResourceOntology.owl#Data_Resource"]
    onts_a = ["BROTEST-0","BROTEST-0","BROTEST-0","BROTEST-0"]
    terms_b = ["http://www.semanticweb.org/associatedmedicine/lavima/2011/10/Ontology1.owl#La_mastication_de_produit",
               "http://www.semanticweb.org/associatedmedicine/lavima/2011/10/Ontology1.owl#Article",
               "http://www.semanticweb.org/associatedmedicine/lavima/2011/10/Ontology1.owl#Maux_de_rein",
               "http://purl.obolibrary.org/obo/MCBCC_0000344#PapillaryInvasiveDuctalTumor"]
    onts_b = ["ONTOMATEST-0","ONTOMATEST-0","ONTOMATEST-0", "MCCLTEST-0"]

    user_creator = LinkedData::Models::User.where.include(:username).page(1,100).first
    if user_creator.nil?
      u = LinkedData::Models::User.new(username: "tim",
                                       email: "tim@example.org",
                                       password: "password")
      u.save
      user_creator = LinkedData::Models::User.where.include(:username).page(1,100).first
    end
    process = LinkedData::Models::MappingProcess.new(
      :creator => user_creator, :name => "TEST Mapping Annotator")
    process.date = DateTime.now
    process.relation = RDF::URI.new("http://bogus.relation.com/predicate")
    process.save

    4.times do |i|
        classes = []
        class_id = terms_a[i]
        ont_acr = onts_a[i]
        sub = LinkedData::Models::Ontology.find(ont_acr).first.latest_submission(status: :any)
        sub.bring(ontology: [:acronym])
        c = LinkedData::Models::Class.find(RDF::URI.new(class_id))
                                    .in(sub)
                                    .first
        classes << c
        class_id = terms_b[i]
        ont_acr = onts_b[i]
        sub = LinkedData::Models::Ontology.find(ont_acr).first.latest_submission(status: :any)
        sub.bring(ontology: [:acronym])
        c = LinkedData::Models::Class.find(RDF::URI.new(class_id))
                                    .in(sub)
                                    .first
        classes << c
        LinkedData::Mappings.create_rest_mapping(classes,process)
    end
  end

end
