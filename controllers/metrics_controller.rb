class MetricsController < ApplicationController
  namespace "/metrics" do

    # Display all metrics
    get do
      check_last_modified_collection(LinkedData::Models::Metric)
      latest_metrics = LinkedData::Models::Metric.where.include(LinkedData::Models::Metric.goo_attrs_to_load(includes_param)).all
                    .group_by { |x| x.id.split('/')[-4] }
                    .transform_values { |metrics| metrics.max_by { |x| x.id.split('/')[-2].to_i } }
      reply latest_metrics.values
    end

    #
    # Note: useful submission status states:
    #LinkedData::Models::SubmissionStatus::VALUES.sort
    #=> ["ANNOTATOR",
    #    "ARCHIVED",
    #    "ERROR_ANNOTATOR",
    #    "ERROR_ARCHIVED",
    #    "ERROR_INDEXED",
    #    "ERROR_METRICS",
    #    "ERROR_OBSOLETE",
    #    "ERROR_RDF",
    #    "ERROR_RDF_LABELS",
    #    "ERROR_UPLOADED",
    #    "INDEXED",
    #    "METRICS",
    #    "OBSOLETE",
    #    "RDF",
    #    "RDF_LABELS",
    #    "UPLOADED"]

    get '/missing' do
      onts = LinkedData::Models::Ontology.where
                                          .include(:acronym, :summaryOnly,
                                                   submissions: [:submissionId, :submissionStatus])
                                          .all
      ontology_submissions = onts.filter_map do |ont|
        next if ont.summaryOnly

        sub = ont.submissions
                 .select { |submission| submission.ready?(status: 'RDF') }
                 .max_by { |submission| submission.submissionId.to_i }
        [ont, sub]
      end

      submissions_with_metrics = ontology_submissions.filter_map do |_ont, sub|
        next if sub.nil?

        status = sub.submissionStatus.map { |s| s.id.to_s.split('/').last }
        sub if status.include?('METRICS') && !status.include?('ERROR_METRICS')
      end

      unless submissions_with_metrics.empty?
        LinkedData::Models::OntologySubmission.where.models(submissions_with_metrics)
                                               .include(:metrics).all
      end

      missing = ontology_submissions.each_with_object(Set.new) do |(ont, sub), result|
        if sub.nil?
          result.add(ont)
          next
        end

        status = sub.submissionStatus.map { |s| s.id.to_s.split('/').last }
        result.add(ont) if status.include?('ERROR_METRICS') ||
                           !status.include?('METRICS') ||
                           sub.metrics.nil?
      end
      reply missing.to_a
    end

  end  # namespace /metrics

  # Display metrics for ontology
  get "/ontologies/:ontology/metrics" do
    check_last_modified_collection(LinkedData::Models::Metric)
    ont = Ontology.find(params['ontology']).first
    error 404, "Ontology #{params['ontology']} not found" unless ont
    ontology_metrics = LinkedData::Models::Metric
                      .where(submission: {ontology: [acronym: params['ontology']]})
                      .order_by(submission: {submissionId: :desc})
                      .include(LinkedData::Models::Metric.goo_attrs_to_load(includes_param)).first
    reply ontology_metrics || {}
  end

  get "/ontologies/:ontology/submissions/:ontology_submission_id/metrics" do
    check_last_modified_collection(LinkedData::Models::Metric)
    ont = Ontology.find(params['ontology']).first
    error 404, "Ontology #{params['ontology']} not found" unless ont
    ontology_submission_metrics = LinkedData::Models::Metric
                      .where(submission: { submissionId: params['ontology_submission_id'].to_i, ontology: [acronym: params['ontology']] })
                      .include(LinkedData::Models::Metric.goo_attrs_to_load(includes_param)).first
    reply ontology_submission_metrics || {}
  end


end
