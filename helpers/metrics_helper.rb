require 'sinatra/base'

module Sinatra
  module Helpers
    module MetricsHelper
      # Metrics of the ontology's highest submission that has them.
      #
      # Looks the submission up first and then loads its one Metrics record by id. Querying
      # Metric through submission and ontology instead becomes a join across the Metrics,
      # OntologySubmission and Ontology graphs over every submission, which takes minutes on
      # AllegroGraph for ontologies with many submissions.
      def latest_ontology_metrics(ont)
        latest = ont.latest_submission(status: :any, include: [:metrics])
        return nil if latest.nil?
        return load_metrics(latest.metrics) if latest.metrics

        # The newest submission has no metrics yet (still processing, or ERROR_METRICS). Fall
        # back to the newest one that does. Archiving replaces a submission's statuses with
        # ARCHIVED but keeps its metrics, so look at both.
        older = [[:metrics], [:archived]].filter_map do |status|
          ont.latest_submission(status: status, include: [:metrics])
        end
        load_metrics(older.select(&:metrics).max_by(&:submissionId)&.metrics)
      end

      def submission_metrics(ont, submission_id)
        load_metrics(ont.submission(submission_id, include: [:metrics])&.metrics)
      end

      def load_metrics(metrics)
        return nil if metrics.nil?

        LinkedData::Models::Metric.find(metrics.id)
                                  .include(LinkedData::Models::Metric.goo_attrs_to_load(includes_param)).first
      end
    end
  end
end

helpers Sinatra::Helpers::MetricsHelper
