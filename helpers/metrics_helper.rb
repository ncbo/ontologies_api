require 'sinatra/base'

module Sinatra
  module Helpers
    module MetricsHelper
      # The ontology a per-ontology metrics route is for, with the access check. Metric has no
      # read restriction of its own, so the check in `reply` lets a private ontology's metrics
      # through; check the ontology here instead.
      def metrics_ontology
        ont = LinkedData::Models::Ontology.find(params['ontology'])
                                          .include(:acronym, :administeredBy, :acl, :viewingRestriction).first
        error 404, "Ontology #{params['ontology']} not found" unless ont
        check_access(ont) if LinkedData.settings.enable_security
        ont
      end

      # Drops the metrics of ontologies the current user can't read. Metric has no read restriction
      # of its own, so `reply` would return every ontology's metrics, private ones included.
      # Metric ids are <ontology id>/submissions/<n>/metrics.
      def readable_metrics(metrics)
        return metrics unless LinkedData.settings.enable_security

        ontologies = LinkedData::Models::Ontology.where
                                                 .include(:acronym, *LinkedData::Models::Ontology.access_control_load_attrs)
                                                 .all
        hidden = ontologies.select { |o| o.read_restricted? && !o.readable?(env['REMOTE_USER']) }
                           .map { |o| o.id.to_s }.to_set
        return metrics if hidden.empty?

        metrics.reject { |m| hidden.include?(m.id.to_s.split('/submissions/').first) }
      end

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
