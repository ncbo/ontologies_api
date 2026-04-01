require_relative '../test_case'

class TestSearchModelsController < TestCase

  def after_suite
    LinkedData::SampleData::Ontology.delete_ontologies_and_submissions
    LinkedData::Models::Ontology.indexClear
    LinkedData::Models::Class.indexClear
    LinkedData::Models::OntologyProperty.indexClear
    Goo.init_search_connection(:ontology_data)
  end

  def setup
    after_suite
  end

  def test_show_all_collection
    get '/admin/search/collections'
    assert last_response.ok?
    res = MultiJson.load(last_response.body)
    required = %w[ontology_data ontology_metadata prop_search_core1 term_search_core1]
    allowed_extra = %w[term_search test_solr]
    collections = res["collections"]
    assert_empty required - collections
    assert_empty collections - (required + allowed_extra)
  end

  def test_collection_schema
    get '/admin/search/collections'
    assert last_response.ok?
    res = MultiJson.load(last_response.body)
    collection = res["collections"].first
    refute_nil collection
    get "/admin/search/collections/#{collection}/schema"
    assert last_response.ok?
    res = MultiJson.load(last_response.body)
    fields = res["fields"].map { |x| x["name"] }
    assert_includes fields, 'id'
    assert_includes fields, 'resource_id'
    assert_includes fields, 'resource_model'
  end

  def test_collection_search
    LinkedData::SampleData::Ontology.create_ontologies_and_submissions({
                                                                        process_submission: false,
                                                                        acronym: "BROSEARCHTEST",
                                                                        name: "BRO Search Test",
                                                                        file_path: "./test/data/ontology_files/BRO_v3.2.owl",
                                                                        ont_count: 1,
                                                                        submission_count: 1,
                                                                        ontology_type: "VALUE_SET_COLLECTION"
                                                                      })
    collection = 'ontology_metadata'
    post "/admin/search/collections/#{collection}/search", {q: ""}

    assert last_response.ok?
    res = MultiJson.load(last_response.body)
    assert_equal 2,  res['response']['numFound']
  end

  def test_search_security
    _, _, bro = LinkedData::SampleData::Ontology.create_ontologies_and_submissions({
                                                                                    process_submission: true,
                                                                                    process_options: { process_rdf: true, extract_metadata: false, generate_missing_labels: false},
                                                                                    acronym: "BROSEARCHTEST",
                                                                                    name: "BRO Search Test",
                                                                                    file_path: "./test/data/ontology_files/BRO_v3.2.owl",
                                                                                    ont_count: 1,
                                                                                    submission_count: 1,
                                                                                    ontology_type: "VALUE_SET_COLLECTION"
                                                                                  })

    LinkedData::SampleData::Ontology.create_ontologies_and_submissions({
                                                                         process_submission: true,
                                                                         process_options: { process_rdf: true, extract_metadata: false, generate_missing_labels: false},
                                                                         acronym: "MCCLSEARCHTEST",
                                                                         name: "MCCL Search Test",
                                                                         file_path: "./test/data/ontology_files/CellLine_OWL_BioPortal_v1.0.owl",
                                                                         ont_count: 1,
                                                                         submission_count: 1
                                                                       })
    subs = LinkedData::Models::OntologySubmission.all

    subs.each do |s|
      s.bring_remaining
      s.index_all(Logger.new($stdout))
    end

    allowed_user1 = User.new({
                               username: "allowed1",
                               email: "test1@example.org",
                               password: "12345"
                             })
    allowed_user1.save

    allowed_user2 = User.new({
                               username: "allowed2",
                               email: "test2@example.org",
                               password: "12345"
                             })
    allowed_user2.save

    blocked_user = User.new({
                              username: "blocked",
                              email: "test3@example.org",
                              password: "12345"
                            })
    blocked_user.save

    bro =  bro.first
    bro.bring_remaining
    bro.acl = [allowed_user1, allowed_user2]
    bro.viewingRestriction = "private"
    bro.save

    begin
      self.class.enable_security

      get "/search/ontologies?query=#{bro.acronym}&apikey=#{blocked_user.apikey}"
      response = MultiJson.load(last_response.body)["collection"]
      assert_empty response.select{|x| x["ontology_acronym_text"].eql?(bro.acronym)}

      get "/search/ontologies/content?q=*Research_Lab_Management*&apikey=#{blocked_user.apikey}"
      assert last_response.ok?
      res = MultiJson.load(last_response.body)
      assert_equal 0, res['totalCount']

      get "/search/ontologies?query=#{bro.acronym}&apikey=#{allowed_user1.apikey}"
      response = MultiJson.load(last_response.body)["collection"]
      refute_empty response.select{|x| x["ontology_acronym_text"].eql?(bro.acronym)}

      get "/search/ontologies/content?q=*Research_Lab_Management*&apikey=#{allowed_user1.apikey}"
      assert last_response.ok?
      res = MultiJson.load(last_response.body)
      assert_equal 1, res['totalCount']

      self.class.reset_security(false)
    ensure
      self.class.disable_security
    end
  end

  def test_ontology_metadata_search
    LinkedData::SampleData::Ontology.create_ontologies_and_submissions({
                                                                        process_submission: false,
                                                                        acronym: "BROSEARCHTEST",
                                                                        name: "BRO Search Test",
                                                                        file_path: "./test/data/ontology_files/BRO_v3.2.owl",
                                                                        ont_count: 1,
                                                                        submission_count: 1,
                                                                        ontology_type: "VALUE_SET_COLLECTION"
                                                                      })

    LinkedData::SampleData::Ontology.create_ontologies_and_submissions({
                                                                       process_submission: false,
                                                                       acronym: "MCCLSEARCHTEST",
                                                                       name: "MCCL Search Test",
                                                                       file_path: "./test/data/ontology_files/CellLine_OWL_BioPortal_v1.0.owl",
                                                                       ont_count: 1,
                                                                       submission_count: 1
                                                                     })
    # Search ACRONYM
    ## full word
    get '/search/ontologies?query=BROSEARCHTEST-0'
    response = MultiJson.load(last_response.body)["collection"]
    assert_equal 'BROSEARCHTEST-0', response.first['ontology_acronym_text']

    ### start
    get '/search/ontologies?query=BROSEARCHTEST'
    response = MultiJson.load(last_response.body)["collection"]
    assert_equal 'BROSEARCHTEST-0', response.first['ontology_acronym_text']

    ## part of the word
    get '/search/ontologies?query=BRO'
    response = MultiJson.load(last_response.body)["collection"]
    assert_equal 'BROSEARCHTEST-0', response.first['ontology_acronym_text']


    # Search name
    ## full word
    ### start
    get '/search/ontologies?query=MCCL Search'
    response = MultiJson.load(last_response.body)["collection"]
    assert_equal 'MCCLSEARCHTEST-0', response.first['ontology_acronym_text']
    ###in the middle
    get '/search/ontologies?query=Search Test'
    response = MultiJson.load(last_response.body)["collection"]
    assert_equal 2, response.size
    assert_equal 'BROSEARCHTEST-0', response.first['ontology_acronym_text']
    assert_equal 'MCCLSEARCHTEST-0', response.last['ontology_acronym_text']
    ## part of the word
    ### start
    get '/search/ontologies?query=MCCL Sea'
    response = MultiJson.load(last_response.body)["collection"]
    assert_equal 'MCCLSEARCHTEST-0', response.first['ontology_acronym_text']
    ### in the middle
    get '/search/ontologies?query=Sea'
    response = MultiJson.load(last_response.body)["collection"]
    assert_equal 2, response.size
    assert_equal 'BROSEARCHTEST-0', response.first['ontology_acronym_text']
    assert_equal 'MCCLSEARCHTEST-0', response.last['ontology_acronym_text']


    ## full text
    get '/search/ontologies?query=MCCL Search Test'
    response = MultiJson.load(last_response.body)["collection"]
    assert_equal 'MCCLSEARCHTEST-0', response.first['ontology_acronym_text']


    # Search description
    ## full word
    ### start
    get '/search/ontologies?query=Description'
    response = MultiJson.load(last_response.body)["collection"]
    assert_equal 2, response.size
    assert_equal 'BROSEARCHTEST-0', response.first['ontology_acronym_text']
    assert_equal 'MCCLSEARCHTEST-0', response.last['ontology_acronym_text']

    ### in the middle
    get '/search/ontologies?query=1'
    response = MultiJson.load(last_response.body)["collection"]
    assert_equal 2, response.size
    assert_equal 'BROSEARCHTEST-0', response.first['ontology_acronym_text']
    assert_equal 'MCCLSEARCHTEST-0', response.last['ontology_acronym_text']

    ## part of the word
    ### start
    get '/search/ontologies?query=Desc'
    response = MultiJson.load(last_response.body)["collection"]
    assert_equal 2, response.size
    assert_equal 'BROSEARCHTEST-0', response.first['ontology_acronym_text']
    assert_equal 'MCCLSEARCHTEST-0', response.last['ontology_acronym_text']

    ### full text
    get '/search/ontologies?query=Description 1'
    response = MultiJson.load(last_response.body)["collection"]
    assert_equal 2, response.size
    assert_equal 'BROSEARCHTEST-0', response.first['ontology_acronym_text']
    assert_equal 'MCCLSEARCHTEST-0', response.last['ontology_acronym_text']
  end

  def test_ontology_metadata_filters
    num_onts_created, created_ont_acronyms, ontologies = create_ontologies_and_submissions(ont_count: 10, submission_count: 1)

    group1 = LinkedData::Models::Group.find('group-1').first || LinkedData::Models::Group.new(acronym: 'group-1', name: "Test Group 1").save
    group2 = LinkedData::Models::Group.find('group-2').first || LinkedData::Models::Group.new(acronym: 'group-2', name: "Test Group 2").save
    category1 = LinkedData::Models::Category.find('category-1').first || LinkedData::Models::Category.new(acronym: 'category-1', name: "Test Category 1").save
    category2 = LinkedData::Models::Category.find('category-2').first || LinkedData::Models::Category.new(acronym: 'category-2', name: "Test Category 2").save

    ontologies1 = ontologies[0..5].each do |o|
      o.bring_remaining
      o.group = [group1]
      o.hasDomain = [category1]
      o.save
    end

    ontologies2 = ontologies[6..8].each do |o|
      o.bring_remaining
      o.group = [group2]
      o.hasDomain = [category2]
      o.save
    end

    # test filter by group and category
    get "/search/ontologies?page=1&pagesize=100&groups=#{group1.acronym}"
    assert last_response.ok?
    assert_equal ontologies1.size, MultiJson.load(last_response.body)["collection"].length
    get "/search/ontologies?page=1&pagesize=100&groups=#{group2.acronym}"
    assert last_response.ok?
    assert_equal ontologies2.size, MultiJson.load(last_response.body)["collection"].length

    get "/search/ontologies?page=1&pagesize=100&groups=#{group1.acronym},#{group2.acronym}"
    assert last_response.ok?
    assert_equal ontologies1.size  + ontologies2.size, MultiJson.load(last_response.body)["collection"].length

    get "/search/ontologies?page=1&pagesize=100&hasDomain=#{category1.acronym}"
    assert last_response.ok?
    assert_equal ontologies1.size, MultiJson.load(last_response.body)["collection"].length

    get "/search/ontologies?page=1&pagesize=100&hasDomain=#{category2.acronym}"
    assert last_response.ok?
    assert_equal ontologies2.size, MultiJson.load(last_response.body)["collection"].length

    get "/search/ontologies?page=1&pagesize=100&hasDomain=#{category2.acronym},#{category1.acronym}"
    assert last_response.ok?
    assert_equal ontologies1.size + ontologies2.size, MultiJson.load(last_response.body)["collection"].length

    get "/search/ontologies?page=1&pagesize=100&hasDomain=#{category2.acronym}&groups=#{group1.acronym}"
    assert last_response.ok?
    assert_equal 0, MultiJson.load(last_response.body)["collection"].length
    get "/search/ontologies?page=1&pagesize=100&hasDomain=#{category2.acronym}&groups=#{group2.acronym}"
    assert last_response.ok?
    assert_equal ontologies2.size, MultiJson.load(last_response.body)["collection"].length

    ontologies3 = ontologies[9]
    ontologies3.bring_remaining
    ontologies3.group = [group1, group2]
    ontologies3.hasDomain = [category1, category2]
    ontologies3.name = "name search test"
    ontologies3.save

    ontologies.first.name = "sort by test"
    ontologies.first.save
    sub = ontologies.first.latest_submission(status: :any).bring_remaining
    sub.status = 'retired'
    sub.description = "234"
    sub.creationDate = DateTime.yesterday.to_datetime
    sub.hasOntologyLanguage = LinkedData::Models::OntologyFormat.find('SKOS').first
    sub.save

    #test search with sort
    get "/search/ontologies?page=1&pagesize=100&q=tes&sort=ontology_name_sort asc"
    assert last_response.ok?
    submissions = MultiJson.load(last_response.body)

    refute_empty submissions["collection"]
    assert_equal ontologies.map{|x| x.bring(:name).name}.sort, submissions["collection"].map{|x| x["ontology_name_text"]}

    get "/search/ontologies?page=1&pagesize=100&q=tes&sort=creationDate_dt desc"

    assert last_response.ok?
    submissions = MultiJson.load(last_response.body)
    refute_empty submissions["collection"]
    assert_equal ontologies.map{|x| x.latest_submission(status: :any).bring(:creationDate).creationDate.to_s.split('T').first}.sort.reverse,
                 submissions["collection"].map{|x| x["creationDate_dt"].split('T').first}

    # test search with format
    get "/search/ontologies?page=1&pagesize=100&q=tes&hasOntologyLanguage=SKOS"
    assert last_response.ok?
    submissions = MultiJson.load(last_response.body)

    refute_empty submissions["collection"]
    assert_equal 1, submissions["collection"].size

    get "/search/ontologies?page=1&pagesize=100&q=tes&hasOntologyLanguage=OWL"
    assert last_response.ok?
    submissions = MultiJson.load(last_response.body)
    refute_empty submissions["collection"]
    assert_equal ontologies.size-1 , submissions["collection"].size

    # test ontology filter with submission filter attributes
    get "/search/ontologies?page=1&pagesize=100&q=tes&groups=group-2&hasDomain=category-2&hasOntologyLanguage=OWL"
    assert last_response.ok?
    submissions = MultiJson.load(last_response.body)
    refute_empty submissions["collection"]
    assert_equal ontologies2.size + 1 , submissions["collection"].size

    # test ontology filter with status
    get "/search/ontologies?page=1&pagesize=100&status=retired"
    assert last_response.ok?
    submissions = MultiJson.load(last_response.body)
    refute_empty submissions["collection"]
    assert_equal 1 , submissions["collection"].size

    get "/search/ontologies?page=1&pagesize=100&status=alpha,beta,production"
    assert last_response.ok?
    submissions = MultiJson.load(last_response.body)
    refute_empty submissions["collection"]
    assert_equal ontologies.size - 1 , submissions["collection"].size

    get "/search/ontologies?page=1&pagesize=100&q=234"
    assert last_response.ok?
    submissions = MultiJson.load(last_response.body)
    assert_equal "http://data.bioontology.org/ontologies/TEST-ONT-0/submissions/1" , submissions["collection"].first["id"]
  end

  def test_search_data
    LinkedData::SampleData::Ontology.create_ontologies_and_submissions({
                                                                        process_submission: true,
                                                                        process_options: { process_rdf: true, extract_metadata: false,  index_all_data: true, generate_missing_labels: false},
                                                                        acronym: "BROSEARCHTEST",
                                                                        name: "BRO Search Test",
                                                                        file_path: "./test/data/ontology_files/BRO_v3.2.owl",
                                                                        ont_count: 1,
                                                                        submission_count: 1,
                                                                        ontology_type: "VALUE_SET_COLLECTION"
                                                                      })

    LinkedData::SampleData::Ontology.create_ontologies_and_submissions({
                                                                         process_submission: true,
                                                                         process_options: { process_rdf: true, extract_metadata: false, index_all_data: true, generate_missing_labels: false},
                                                                         acronym: "MCCLSEARCHTEST",
                                                                         name: "MCCL Search Test",
                                                                         file_path: "./test/data/ontology_files/CellLine_OWL_BioPortal_v1.0.owl",
                                                                         ont_count: 1,
                                                                         submission_count: 1
                                                                       })
    subs = LinkedData::Models::OntologySubmission.all
    count = []
    subs.each do |s|
      count << Goo.sparql_query_client.query("SELECT  (COUNT( DISTINCT ?id) as ?c)  FROM <#{s.id}> WHERE {?id ?p ?v}")
                  .first[:c]
                  .to_i
    end

    get "/search/ontologies/content?q=*"
    assert last_response.ok?
    res = MultiJson.load(last_response.body)
    assert_equal count.sum, res['totalCount']

    get "/search/ontologies/content?q=*&ontologies=MCCLSEARCHTEST-0,BROSEARCHTEST-0"
    assert last_response.ok?
    res = MultiJson.load(last_response.body)
    assert_equal count.sum, res['totalCount']

    get "/search/ontologies/content?q=*&ontologies=BROSEARCHTEST-0"
    assert last_response.ok?
    res = MultiJson.load(last_response.body)
    assert_includes count, res['totalCount']

    get "/search/ontologies/content?q=*&ontologies=MCCLSEARCHTEST-0"
    assert last_response.ok?
    res = MultiJson.load(last_response.body)
    assert_includes count, res['totalCount']
  end

end
