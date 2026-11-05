require_relative '../test_case'

module MetricsGooQueryCountSpy
  def query(*args, **kwargs, &block)
    count = Thread.current[:metrics_goo_query_count]
    Thread.current[:metrics_goo_query_count] = count + 1 unless count.nil?
    Thread.current[:metrics_goo_queries]&.push(args.first.to_s)
    super
  end
end

unless Goo::SPARQL::Client.ancestors.include?(MetricsGooQueryCountSpy)
  Goo::SPARQL::Client.prepend(MetricsGooQueryCountSpy)
end

class TestMetricsController < TestCase

  def count_sparql_queries
    Thread.current[:metrics_goo_query_count] = 0
    yield
    Thread.current[:metrics_goo_query_count]
  ensure
    Thread.current[:metrics_goo_query_count] = nil
  end

  def capture_sparql_queries
    Thread.current[:metrics_goo_queries] = []
    yield
    Thread.current[:metrics_goo_queries]
  ensure
    Thread.current[:metrics_goo_queries] = nil
  end

  # @@data holds the values for submission 2; submission 1 is loaded from a different file
  def assert_metrics_of_submission(metrics, ontology, submission_id, values: @@data)
    assert metrics['@id'].end_with?("/ontologies/#{ontology}/submissions/#{submission_id}/metrics"),
           "Expected metrics of #{ontology} submission #{submission_id}, got #{metrics['@id']}"
    values.each { |k, v| assert_equal(v, metrics[k]) }
  end

  def before_suite
    if OntologySubmission.all.count > 100
      puts "this test is going to wipe out all submission and ontologies. probably this is not a test env."
      return
    end
    OntologySubmission.all.each {|s| s.delete }
    Ontology.all.each {|o| o.delete }
    @@data = {"classes" => 487,
              "averageChildCount" => 5,
              "maxChildCount" => 65,
              "classesWithOneChild" => 14,
              "classesWithMoreThan25Children" => 2,
              "classesWithNoDefinition" => 11,
              "individuals" => 124,
              "properties" => 63,
              "maxDepth" => 7 }
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
      @@data.each do |k, v|
        assert_equal(v, m[k])
      end
      assert m["@id"] == m["submission"].first + "/metrics"
    end
  end

  def test_single_metrics
    # Submission 3 is the newest but was never processed, so the metrics come from submission 2
    ontology = 'TEST-ONT-0'
    get "/ontologies/#{ontology}/metrics"
    assert last_response.ok?
    assert_metrics_of_submission(MultiJson.load(last_response.body), ontology, 2)
  end

  def test_single_metrics_does_not_join_metrics_through_ontology
    queries = capture_sparql_queries { get '/ontologies/TEST-ONT-0/metrics' }
    assert last_response.ok?
    joins = queries.select { |q| q.include?('metadata/Metrics') && q.include?('metadata/Ontology>') }
    assert_empty joins, "Expected no query joining Metrics through Ontology:\n#{joins.join("\n")}"
  end

  def test_single_metrics_falls_back_to_archived_submission
    # Archiving replaces a submission's statuses with ARCHIVED but keeps its metrics
    ontology = 'TEST-ONT-1'
    sub = OntologySubmission.where(ontology: [acronym: ontology], submissionId: 2).first
    sub.bring_remaining
    original_status = sub.submissionStatus.dup
    sub.submissionStatus = [SubmissionStatus.find('ARCHIVED').first]
    sub.save

    get "/ontologies/#{ontology}/metrics"
    assert last_response.ok?
    assert_metrics_of_submission(MultiJson.load(last_response.body), ontology, 2)
  ensure
    if sub && original_status
      sub.submissionStatus = original_status
      sub.save
    end
  end

  def test_single_metrics_unknown_ontology
    get '/ontologies/NO-SUCH-ONT/metrics'
    assert_equal 404, last_response.status
    get '/ontologies/NO-SUCH-ONT/submissions/1/metrics'
    assert_equal 404, last_response.status
  end

  def test_metrics_with_submission_id
    ontology = 'TEST-ONT-0'
    get "/ontologies/#{ontology}/submissions/2/metrics"
    assert last_response.ok?
    assert_metrics_of_submission(MultiJson.load(last_response.body), ontology, 2)

    get "/ontologies/#{ontology}/submissions/1/metrics"
    assert last_response.ok?
    assert_metrics_of_submission(MultiJson.load(last_response.body), ontology, 1, values: {})

    # Submission 3 was never processed and submission 99 does not exist
    [3, 99].each do |submission_id|
      get "/ontologies/#{ontology}/submissions/#{submission_id}/metrics"
      assert last_response.ok?
      assert_equal({}, MultiJson.load(last_response.body))
    end
  end

  def test_private_ontology_metrics_need_access
    ontology = 'TEST-ONT-1'
    allowed, other = %w[metrics_acl_user metrics_other_user].map do |username|
      user = LinkedData::Models::User.new(username: username, email: "#{username}@example.org",
                                          password: 'metrics_test_pass')
      user.save
      user.bring_remaining
      user
    end
    ont = Ontology.find(ontology).first
    ont.bring_remaining
    original = { viewingRestriction: ont.viewingRestriction, acl: ont.acl }
    ont.viewingRestriction = 'private'
    ont.acl = [allowed]
    ont.save

    with_settings(enable_security: true) do
      ["/ontologies/#{ontology}/metrics", "/ontologies/#{ontology}/submissions/2/metrics"].each do |path|
        get path, apikey: other.apikey
        assert_equal 403, last_response.status, "#{path} for a user without access"
        get path, apikey: allowed.apikey
        assert last_response.ok?, "#{path} for a user on the ACL"
        assert_metrics_of_submission(MultiJson.load(last_response.body), ontology, 2)
      end
    end
  ensure
    if ont && original
      ont.viewingRestriction = original[:viewingRestriction]
      ont.acl = original[:acl] || []
      ont.save
    end
    [allowed, other].compact.each(&:delete)
  end

  def test_metrics_with_submission_id_as_param
    ontology = 'TEST-ONT-0'
    get "/ontologies/#{ontology}/metrics?ontology_submission_id=2"
    assert last_response.ok?
    metrics = MultiJson.load(last_response.body)

    @@data.each do |k,v|
      assert_equal(v, metrics[k])
    end
  end

  def test_metrics_missing
    # test for zero ontologies without metrics (created by before_suite)
    query_count = count_sparql_queries { get '/metrics/missing' }
    assert last_response.ok?
    ontologies = MultiJson.load(last_response.body)
    assert_equal(0, ontologies.length, msg = 'Failure to detect 0 ontologies with missing metrics.')
    assert_equal(2, query_count, 'Expected missing metrics lookup to use two batched SPARQL queries.')
    # create ontologies with latest submissions that have no metrics
    delete_ontologies_and_submissions
    options = { ont_count: 2,
                submission_count: 1,
                process_submission: false,
                random_submission_count: false }
    create_ontologies_and_submissions(options)
    query_count = count_sparql_queries { get '/metrics/missing' }
    assert last_response.ok?
    ontologies = MultiJson.load(last_response.body)
    assert_equal(2, ontologies.length, msg = 'Failure to detect 2 ontologies with missing metrics.')
    assert_equal(%w[TEST-ONT-0 TEST-ONT-1], ontologies.map { |ontology| ontology['acronym'] }.sort)
    assert_equal(2, query_count, 'Expected missing metrics lookup to use two batched SPARQL queries.')
    # recreate the before_suite data (this test might not be the last one to run in the suite)
    delete_ontologies_and_submissions
    create_ontologies_and_submissions(@@options)
  end

end
