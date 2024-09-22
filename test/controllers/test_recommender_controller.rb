require_relative '../test_case'

class TestRecommenderController < TestCase

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
    @@ontologies = LinkedData::SampleData::Ontology.sample_owl_ontologies(process_submission: true)
    annotator = Annotator::Models::NcboAnnotator.new
    annotator.init_redis_for_tests()
    annotator.create_term_cache_from_ontologies(@@ontologies, false)
  end

  def test_recommend_no_params
    params = { }
    get '/recommender', params
    assert last_response.status == 400
  end

  def test_recommend_empty_input
    get '/recommender', {:input => ''}
    assert last_response.status == 400
  end

  def test_recommend_invalid_input_type
    get '/recommender', {:input => 'cell', :input_type => ''}
    assert last_response.status == 400
    get '/recommender', {:input => 'cell', :input_type => 0}
    assert last_response.status == 400
    get '/recommender', {:input => 'cell', :input_type => 3}
    assert last_response.status == 400
    get '/recommender', {:input => 'cell', :input_type => 'aaa'}
    assert last_response.status == 400
  end

  def test_recommend_invalid_output_type
    get '/recommender', {:input => 'cell', :output_type => ''}
    assert last_response.status == 400
    get '/recommender', {:input => 'cell', :output_type => 0}
    assert last_response.status == 400
    get '/recommender', {:input => 'cell', :output_type => 3}
    assert last_response.status == 400
    get '/recommender', {:input => 'cell', :output_type => 'aaa'}
    assert last_response.status == 400
  end

  def test_recommend_invalid_max_elements_set
    get '/recommender', {:input => 'cell', :max_elements_set => ''}
    assert last_response.status == 400
    get '/recommender', {:input => 'cell', :max_elements_set => 0}
    assert last_response.status == 400
    get '/recommender', {:input => 'cell', :max_elements_set => 5}
    assert last_response.status == 400
    get '/recommender', {:input => 'cell', :max_elements_set => 'aaa'}
    assert last_response.status == 400
  end

  def test_recommend_invalid_weights
    get '/recommender', {:input => 'cell', :wc => ''}
    assert last_response.status == 400
    get '/recommender', {:input => 'cell', :ws => ''}
    assert last_response.status == 400
    get '/recommender', {:input => 'cell', :wa => ''}
    assert last_response.status == 400
    get '/recommender', {:input => 'cell', :wd => ''}
    assert last_response.status == 400
    get '/recommender', {:input => 'cell', :wc => -1}
    assert last_response.status == 400
    get '/recommender', {:input => 'cell', :ws => -1}
    assert last_response.status == 400
    get '/recommender', {:input => 'cell', :wa => -1}
    assert last_response.status == 400
    get '/recommender', {:input => 'cell', :wd => -1}
    assert last_response.status == 400
    get '/recommender', {:input => 'cell', :wc => 0, :ws => 0, :wa => 0, :wd => 0}
    assert last_response.status == 400
  end

  def test_recommend_query_default_parameters
    # Default input type, output type and weights will be used
    params = {
        :input => "Ginsenosides chemistry, biosynthesis, analysis, and potential health effects in software concept or data. Ginsenosides are a special group of triterpenoid saponins that can be classified into two groups by the skeleton of their aglycones, namely dammarane- and oleanane-type. Ginsenosides are found nearly exclusively in Panax species (ginseng) and up to now more than 150 naturally occurring ginsenosides have been isolated from roots, leaves/stems, fruits, and/or flower heads of ginseng. The same concept indicates Ginsenosides have been the target of a lot of research as they are believed to be the main active principles behind the claims of ginsengs efficacy. The potential health effects of ginsenosides that are discussed in this chapter include anticarcinogenic, immunomodulatory, anti-inflammatory, antiallergic, antiatherosclerotic, antihypertensive, and antidiabetic effects as well as antistress activity and effects on the central nervous system. Ginsensoides can be metabolized in the stomach (acid hydrolysis) and in the gastrointestinal tract (bacterial hydrolysis) or transformed to other ginsenosides by drying and steaming of ginseng to more bioavailable and bioactive ginsenosides. The metabolization and transformation of intact ginsenosides, which seems to play an important role for their potential health effects, are discussed. Qualitative and quantitative analytical techniques for the analysis of ginsenosides are important in relation to quality control of ginseng products and plant material and for the determination of the effects of processing of plant material as well as for the determination of the metabolism and bioavailability of ginsenosides. Analytical techniques for the analysis of ginsenosides that are described in this chapter are thin-layer chromatography (TLC), high-performance liquid chromatography (HPLC) combined with various detectors, gas chromatography (GC), colorimetry, enzyme immunoassays (EIA), capillary electrophoresis (CE), nuclear magnetic resonance (NMR) spectroscopy, and spectrophotometric methods.",
    }
    get "/recommender", params
    assert last_response.ok?
    recommendations = MultiJson.load(last_response.body)
    assert_instance_of(Array, recommendations)
    assert_equal(3, recommendations.length, msg='Failed to return 3 recommendations')
    rec_1 = recommendations.first
    assert_instance_of(Hash, rec_1)
    assert(rec_1['evaluationScore'] > 0)
    ontologies = rec_1['ontologies']
    assert_equal(1, ontologies.size)
    assert_instance_of(Array, ontologies)
    assert_instance_of(Hash, ontologies.first)
    coverage_result = rec_1['coverageResult']
    assert_instance_of(Hash, coverage_result)
    assert(coverage_result['score'] > 0)
    assert(coverage_result['normalizedScore'] > 0)
    assert(coverage_result['numberTermsCovered'] > 0)
    assert(coverage_result['numberWordsCovered'] > 0)
    assert(coverage_result['annotations'].size > 0)
    specialization_result = rec_1['specializationResult']
    assert_instance_of(Hash, specialization_result)
    assert(specialization_result['score'] > 0)
    assert(specialization_result['normalizedScore'] > 0)
    acceptance_result = rec_1['acceptanceResult']
    assert_instance_of(Hash, acceptance_result)
    detail_result = rec_1['detailResult']
    assert_instance_of(Hash, detail_result)
    rec_2 = recommendations.second
    rec_3 = recommendations.third
    assert(rec_1['evaluationScore'] > rec_2['evaluationScore'])
    assert(rec_2['evaluationScore'] > rec_3['evaluationScore'])
  end

  # Input: Text; Output: single ontologies
  def test_recommend_query_text_single
    params = {
        :input => "An article has been published about hormone antagonists",
        :input_type => 1, :output_type => 1,
        :wc => 0.55, :ws => 0.15, :wa => 0.15, :wd => 0.15
    }
    # Expected ranking:
    # 1st) MCCLTEST-0 -> hormone antagonists
    # 2nd) ONTOMATEST-0 -> article
    get "/recommender", params
    assert last_response.ok?
    recommendations = MultiJson.load(last_response.body)
    assert_equal(2, recommendations.length, msg='Failed to return 2 recommendations')
    rec_1 = recommendations[0]
    rec_2 = recommendations[1]
    assert_equal(rec_1['ontologies'][0]['acronym'], 'MCCLTEST-0')
    assert_equal(rec_1['coverageResult']['annotations'].size, 1)
    assert_equal(rec_1['coverageResult']['annotations'].first['text'], 'HORMONE ANTAGONISTS')
    assert_equal(rec_1['coverageResult']['annotations'].first['from'], 37)
    assert_equal(rec_1['coverageResult']['annotations'].first['to'], 55)
    assert_equal(rec_1['coverageResult']['annotations'].first['matchType'], 'PREF')
    assert_equal(rec_2['ontologies'][0]['acronym'], 'ONTOMATEST-0')
    assert_equal(rec_2['coverageResult']['annotations'].size, 1)
    assert_equal(rec_2['coverageResult']['annotations'].first['text'], 'ARTICLE')
    assert_equal(rec_2['coverageResult']['annotations'].first['from'], 4)
    assert_equal(rec_2['coverageResult']['annotations'].first['to'], 10)
    assert_equal(rec_2['coverageResult']['annotations'].first['matchType'], 'PREF')
  end

  # Input: Text; Output: ontology sets
  def test_recommend_query_text_sets
    params = {
        :input => "An article has been published about hormone antagonists",
        :input_type => 1, :output_type => 2,
        :wc => 0.55, :ws => 0.15, :wa => 0.15, :wd => 0.15
    }
    # Expected ranking:
    # 1st) MCCLTEST-0, ONTOMATEST-0 -> article, hormone antagonists
    get "/recommender", params
    assert last_response.ok?
    recommendations = MultiJson.load(last_response.body)
    assert_equal(1, recommendations.length, msg='Failed to return 1 recommendation')
    rec = recommendations[0]
    ont_acronyms = rec['ontologies'].map { |o| o['acronym']}
    assert_equal(true, (ont_acronyms.include? 'MCCLTEST-0'))
    assert_equal(true, (ont_acronyms.include? 'ONTOMATEST-0'))
    assert_equal(rec['coverageResult']['annotations'].size, 2)
    assert_equal(rec['coverageResult']['annotations'][0]['text'], 'ARTICLE')
    assert_equal(rec['coverageResult']['annotations'][0]['from'], 4)
    assert_equal(rec['coverageResult']['annotations'][0]['to'], 10)
    assert_equal(rec['coverageResult']['annotations'][0]['matchType'], 'PREF')
    assert_equal(rec['coverageResult']['annotations'][1]['text'], 'HORMONE ANTAGONISTS')
    assert_equal(rec['coverageResult']['annotations'][1]['from'], 37)
    assert_equal(rec['coverageResult']['annotations'][1]['to'], 55)
    assert_equal(rec['coverageResult']['annotations'][1]['matchType'], 'PREF')
  end

  # Input: Keywords; Output: single ontologies
  def test_recommend_query_keywords_single
    params = {
        :input => "software development methodology, software, pancreatic hormone, hormone, colorectal carcinoma",
        :input_type => 2, :output_type => 1,
        :wc => 0.55, :ws => 0.15, :wa => 0.15, :wd => 0.15
    }
    # Expected ranking:
    # 1st) MCCLTEST-0 -> hormone, pancreatic hormone
    # 2nd) BROTEST-0 -> software
    get "/recommender", params
    assert last_response.ok?
    recommendations = MultiJson.load(last_response.body)
    assert_equal(2, recommendations.length, msg='Failed to return 2 recommendations')
    rec_1 = recommendations[0]
    rec_2 = recommendations[1]
    assert_equal(rec_1['ontologies'][0]['acronym'], 'MCCLTEST-0')
    assert_equal(rec_1['coverageResult']['annotations'].size, 2)
    assert_equal(rec_1['coverageResult']['annotations'][0]['text'], 'PANCREATIC HORMONE')
    assert_equal(rec_1['coverageResult']['annotations'][0]['from'], 45)
    assert_equal(rec_1['coverageResult']['annotations'][0]['to'], 62)
    assert_equal(rec_1['coverageResult']['annotations'][0]['matchType'], 'PREF')
    assert_equal(rec_1['coverageResult']['annotations'][1]['text'], 'HORMONE')
    assert_equal(rec_1['coverageResult']['annotations'][1]['from'], 65)
    assert_equal(rec_1['coverageResult']['annotations'][1]['to'], 71)
    assert_equal(rec_1['coverageResult']['annotations'][1]['matchType'], 'PREF')
    assert_equal(rec_2['ontologies'][0]['acronym'], 'BROTEST-0')
    assert_equal(rec_2['coverageResult']['annotations'].size, 1)
    assert_equal(rec_2['coverageResult']['annotations'][0]['text'], 'SOFTWARE')
    assert_equal(rec_2['coverageResult']['annotations'][0]['from'], 35)
    assert_equal(rec_2['coverageResult']['annotations'][0]['to'], 42)
    assert_equal(rec_2['coverageResult']['annotations'][0]['matchType'], 'PREF')
  end

  # Input: Keywords; Output: ontology sets
  def test_recommend_query_keywords_sets
    params = {
        :input => "software development methodology, software, pancreatic hormone, hormone, colorectal carcinoma",
        :input_type => 2, :output_type => 2,
        :wc => 0.55, :ws => 0.15, :wa => 0.15, :wd => 0.15
    }
    # Expected ranking:
    # 1st) MCCLTEST-0, BROTEST-0 -> software, hormone, pancreatic hormone
    get "/recommender", params
    assert last_response.ok?
    recommendations = MultiJson.load(last_response.body)
    assert_equal(1, recommendations.length, msg='Failed to return 1 recommendation')
    rec = recommendations[0]
    ont_acronyms = rec['ontologies'].map { |o| o['acronym']}
    assert_equal(true, (ont_acronyms.include? 'MCCLTEST-0'))
    assert_equal(true, (ont_acronyms.include? 'BROTEST-0'))
    assert_equal(rec['coverageResult']['annotations'].size, 3)
    assert_equal(rec['coverageResult']['annotations'][0]['text'], 'SOFTWARE')
    assert_equal(rec['coverageResult']['annotations'][0]['from'], 35)
    assert_equal(rec['coverageResult']['annotations'][0]['to'], 42)
    assert_equal(rec['coverageResult']['annotations'][0]['matchType'], 'PREF')
    assert_equal(rec['coverageResult']['annotations'][1]['text'], 'PANCREATIC HORMONE')
    assert_equal(rec['coverageResult']['annotations'][1]['from'], 45)
    assert_equal(rec['coverageResult']['annotations'][1]['to'], 62)
    assert_equal(rec['coverageResult']['annotations'][1]['matchType'], 'PREF')
    assert_equal(rec['coverageResult']['annotations'][2]['text'], 'HORMONE')
    assert_equal(rec['coverageResult']['annotations'][2]['from'], 65)
    assert_equal(rec['coverageResult']['annotations'][2]['to'], 71)
    assert_equal(rec['coverageResult']['annotations'][2]['matchType'], 'PREF')
  end

end
