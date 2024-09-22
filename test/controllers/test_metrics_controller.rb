require_relative '../test_case'

class TestMetricsController < TestCase

  def self.before_suite
    if OntologySubmission.all.count > 100
      puts "this test is going to wipe out all submission and ontologies. probably this is not a test env."
      return
    end
    OntologySubmission.all.each {|s| s.delete }
    Ontology.all.each {|o| o.delete }
    @@data = {"classes"=>486,
              "averageChildCount"=>5,
              "maxChildCount"=>65,
              "classesWithOneChild"=>14,
              "classesWithMoreThan25Children"=>2,
              "classesWithNoDefinition"=>11,
              "individuals"=>124,
              "properties"=>63,
              "maxDepth"=> 7 }
    @@options = { ont_count: 2,
                  submission_count: 3,
                  submissions_to_process: [1, 2],
                  process_submission: true,
                  process_options: { process_rdf: true, extract_metadata: false, run_metrics: true, index_properties: true },
                  random_submission_count: false }
    LinkedData::SampleData::Ontology.create_ontologies_and_submissions(@@options)
  end

  def test_all_metrics
    get '/metrics'
    assert last_response.ok?
    metrics = MultiJson.load(last_response.body)
    assert metrics.length == 2
    #TODO: improve this test and test for two different ontologies
    #though this is tested in LD
    metrics.each do |m|
      @@data.each do |k,v|
        assert_equal(m[k], v)
      end
      assert m["@id"] == m["submission"].first + "/metrics"
    end
  end

  def test_single_metrics
    ontology = 'TEST-ONT-0'
    get "/ontologies/#{ontology}/metrics"
    assert last_response.ok?
    metrics = MultiJson.load(last_response.body)

    @@data.each do |k,v|
      assert_equal(metrics[k], v)
    end
  end

  def test_metrics_with_submission_id
    ontology = 'TEST-ONT-0'
    get "/ontologies/#{ontology}/submissions/1/metrics"
    assert last_response.ok?
    metrics = MultiJson.load(last_response.body)
    @@data.each do |k,v|
      assert_equal(metrics[k], v)
    end
  end

  def test_metrics_with_submission_id_as_param
    ontology = 'TEST-ONT-0'
    get "/ontologies/#{ontology}/metrics?submissionId=1"
    assert last_response.ok?
    metrics = MultiJson.load(last_response.body)
    @@data.each do |k,v|
      assert_equal(metrics[k], v)
    end
  end

  def test_metrics_missing
    skip "Test takes 160+ seconds to run, disable until we investigate"
    # test for zero ontologies without metrics (created by before_suite)
    get '/metrics/missing'
    assert last_response.ok?
    ontologies = MultiJson.load(last_response.body)
    assert_equal(0, ontologies.length, msg = 'Failure to detect 0 ontologies with missing metrics.')
    # create ontologies with latest submissions that have no metrics
    delete_ontologies_and_submissions
    options = { ont_count: 2,
                submission_count: 1,
                process_submission: false,
                random_submission_count: false }
    create_ontologies_and_submissions(options)
    get '/metrics/missing'
    assert last_response.ok?
    ontologies = MultiJson.load(last_response.body)
    assert_equal(2, ontologies.length, msg = 'Failure to detect 2 ontologies with missing metrics.')
    # recreate the before_suite data (this test might not be the last one to run in the suite)
    delete_ontologies_and_submissions
    create_ontologies_and_submissions(@@options)
  end

end
