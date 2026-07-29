require 'sinatra/base'

module Sinatra
  module Helpers
    module DownloadHelper

      # Formats that can be requested via `download_format`. An empty/absent
      # value streams the original uploaded source file.
      ALLOWED_DOWNLOAD_FORMATS = %w[csv rdf diff].freeze

      ##
      # Single access gate shared by every download endpoint. Enforces, in order:
      #   * read ACL (check_access / read_restricted?)
      #   * license-based download restriction (admins bypass)
      #   * private-ontology accessibility
      def enforce_download_access(ont)
        ont.bring(:viewingRestriction) if ont.bring?(:viewingRestriction)
        check_access(ont)
        restricted = LinkedData::OntologiesAPI.settings.restrict_download.include?(ont.acronym)
        error 403, "License restrictions on download for #{ont.acronym}" if restricted && !current_user.admin?
        error 403, "Ontology #{ont.acronym} is not accessible to your user" if ont.restricted? && !ont.accessible?(current_user)
      end

      ##
      # Resolve the file for a submission + requested format and stream it.
      # Shared by the ontology-latest, specific-submission, and diff routes so
      # format handling, missing-file guards, and streaming live in one place.
      def send_submission_download(ont, submission, download_format)
        download_format = download_format.to_s.downcase

        unless download_format.empty? || ALLOWED_DOWNLOAD_FORMATS.include?(download_format)
          error 400, "Invalid download format: #{download_format}."
        end

        file_path = resolve_download_path(ont, submission, download_format)

        error 404, "No #{download_format.empty? ? 'source' : download_format} file is available for this submission" if file_path.to_s.empty?
        error 404, "Download file is not readable: #{File.basename(file_path)}" unless File.readable?(file_path)

        # Downloads are large (often hundreds of MB) ontology files streamed from
        # disk. Mark them no-store so the global Rack::Cache (Redis entitystore)
        # does not buffer the body into Redis — doing so defeats send_file's
        # streaming and makes serving a cached hit a multi-second Redis GET.
        cache_control :no_store

        send_file file_path, filename: File.basename(file_path)
      end

      private

      def resolve_download_path(ont, submission, download_format)
        case download_format
        when ""
          submission.bring(:uploadFilePath) if submission.bring?(:uploadFilePath)
          submission.uploadFilePath
        when "rdf"
          submission.rdf_path
        when "diff"
          submission.bring(:diffFilePath) if submission.bring?(:diffFilePath)
          submission.diffFilePath
        when "csv"
          # The CSV is an index artifact that only survives for the current
          # (highest-id) submission; the archiver deletes it for older ones.
          unless ont.latest_submission&.id == submission.id
            error 400, "CSV download is only available for the latest submission of #{ont.acronym}."
          end
          submission.bring(ontology: [:acronym])
          submission.csv_path
        end
      end
    end
  end
end

helpers Sinatra::Helpers::DownloadHelper
