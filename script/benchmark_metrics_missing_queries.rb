require_relative '../test/test_case'

module MetricsMissingQueryCounter
  def query(*args, **kwargs, &block)
    count = Thread.current[:metrics_missing_query_count]
    Thread.current[:metrics_missing_query_count] = count + 1 unless count.nil?
    super
  end
end

unless Goo::SPARQL::Client.ancestors.include?(MetricsMissingQueryCounter)
  Goo::SPARQL::Client.prepend(MetricsMissingQueryCounter)
end

class BenchmarkMetricsMissingQueries < TestCase
  PROCESSED_OPTIONS = {
    ont_count: 2,
    submission_count: 3,
    submissions_to_process: [1, 2],
    process_submission: true,
    process_options: {
      process_rdf: true,
      extract_metadata: false,
      run_metrics: true,
      index_properties: true
    },
    random_submission_count: false
  }.freeze

  NO_RDF_OPTIONS = {
    ont_count: 2,
    submission_count: 1,
    process_submission: false,
    random_submission_count: false
  }.freeze

  def before_suite
    raise 'Refusing to replace a non-test dataset' if OntologySubmission.all.count > 100

    delete_ontologies_and_submissions
    create_ontologies_and_submissions(PROCESSED_OPTIONS)
  end

  def test_query_counts
    processed = measure_request
    assert_equal([], processed.fetch(:acronyms))

    delete_ontologies_and_submissions
    create_ontologies_and_submissions(NO_RDF_OPTIONS)

    no_rdf = measure_request
    assert_equal(%w[TEST-ONT-0 TEST-ONT-1], no_rdf.fetch(:acronyms))

    puts "METRICS_MISSING_BENCHMARK=#{JSON.generate(processed: processed, no_rdf: no_rdf)}"
  end

  private

  def measure_request
    Thread.current[:metrics_missing_query_count] = 0
    get '/metrics/missing'
    query_count = Thread.current[:metrics_missing_query_count]

    assert last_response.ok?
    response = MultiJson.load(last_response.body)
    {
      queries: query_count,
      acronyms: response.map { |ontology| ontology.fetch('acronym') }.sort
    }
  ensure
    Thread.current[:metrics_missing_query_count] = nil
  end
end
