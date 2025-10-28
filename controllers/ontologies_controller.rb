require 'time'

class OntologiesController < ApplicationController

  namespace "/ontologies" do

    ##
    # Display all ontologies
    get do
      onts = nil
      check_last_modified_collection(Ontology)
      allow_views = params['also_include_views'] ||= false
      if allow_views
        onts = Ontology.where.include(Ontology.goo_attrs_to_load(includes_param)).to_a
      else
        onts = Ontology.where.filter(Goo::Filter.new(:viewOf).unbound).include(Ontology.goo_attrs_to_load(includes_param)).to_a
      end
      reply onts
    end

    ##
    # Display the most recent submission of the ontology
    get '/:acronym' do
      ont = Ontology.find(params["acronym"]).first
      error 404, "You must provide a valid `acronym` to retrieve an ontology" if ont.nil?
      check_last_modified(ont)
      ont.bring(*Ontology.goo_attrs_to_load(includes_param))
      reply ont
    end

    ##
    # Ontology latest submission
    get "/:acronym/latest_submission" do
      ont = Ontology.find(params["acronym"]).first
      error 404, "You must provide a valid `acronym` to retrieve an ontology" if ont.nil?
      include_status = params["include_status"]
      ont.bring(:acronym, :submissions)

      if include_status
        latest = ont.latest_submission(status: include_status.to_sym)
      else
        latest = ont.latest_submission(status: :any)
      end

      if latest
        check_last_modified(latest)
        latest.bring(*submission_include_params)
      end

      reply(latest || {})
    end

    # on demand ontology pull
    post "/:acronym/pull" do
      LOGGER.info "Forcing the pull and processing of ontology #{params['acronym']}"
      actions = NcboCron::Models::OntologySubmissionParser::ACTIONS.dup
      actions[:remote_pull] = true
      ont = Ontology.find(params["acronym"]).first
      error 404, "You must provide a valid `acronym` to retrieve an ontology" if ont.nil?
      ont.bring(:acronym, :submissions, :viewingRestriction, :administeredBy)
      check_write_access(ont)
      latest = ont.latest_submission(status: :any)
      error 404, "Ontology #{params["acronym"]} contains no submissions" if latest.nil?
      check_last_modified(latest)
      latest.bring(*OntologySubmission.goo_attrs_to_load(includes_param))
      error 404, "Ontology #{params["acronym"]} is not configured to be remotely pulled" unless latest.remote_pulled?
      NcboCron::Models::OntologySubmissionParser.new.queue_submission(latest, actions)
      LOGGER.info "Ontology #{params['acronym']} has been queued for pull and processing"
      halt 204
    end

    ##
    # Create an ontology
    post do
      create_ontology
    end

    ##
    # Create an ontology with constructed URL
    put '/:acronym' do
      create_ontology
    end

    ##
    # Update an ontology
    patch '/:acronym' do
      ont = Ontology.find(params["acronym"]).include(Ontology.attributes).first
      error 422, "You must provide an existing `acronym` to patch" if ont.nil?

      populate_from_params(ont, params)
      if ont.valid?
        ont.save
      else
        error 422, ont.errors
      end

      halt 204
    end

    ##
    # Delete an ontology and all its versions
    delete '/:acronym' do
      ont = Ontology.find(params["acronym"]).first
      error 422, "You must provide an existing `acronym` to delete" if ont.nil?
      ont.delete
      # update ontologies report file, if exists
      NcboCron::Models::OntologiesReport.new.delete_ontologies_from_report([params["acronym"]])
      halt 204
    end

    ##
    # Download the latest submission for an ontology
    get '/:acronym/download' do
      acronym = params["acronym"]
      ont = Ontology.find(acronym).include(Ontology.goo_attrs_to_load).first
      error 422, "You must provide an existing `acronym` to download" if ont.nil?
      ont.bring(:viewingRestriction) if ont.bring?(:viewingRestriction)
      check_access(ont)
      restricted_download = LinkedData::OntologiesAPI.settings.restrict_download.include?(acronym)
      error 403, "License restrictions on download for #{acronym}" if restricted_download && !current_user.admin?
      error 403, "Ontology #{acronym} is not accessible to your user" if ont.restricted? && !ont.accessible?(current_user)
      latest_submission = ont.latest_submission(status: :rdf) # Should resolve to latest successfully loaded submission
      error 404, "There is no latest submission loaded for download" if latest_submission.nil?
      latest_submission.bring(:uploadFilePath)

      download_format = params["download_format"].to_s.downcase
      allowed_formats = ["csv", "rdf"]
      if download_format.empty?
        file_path = latest_submission.uploadFilePath
      elsif ([download_format] - allowed_formats).length > 0
        error 400, "Invalid download format: #{download_format}."
      elsif download_format.eql?("csv")
        latest_submission.bring(ontology: [:acronym])
        file_path = latest_submission.csv_path
      elsif download_format.eql?("rdf")
        file_path = latest_submission.rdf_path
      end

      if File.readable? file_path
        send_file file_path, :filename => File.basename(file_path)
      else
        error 500, "Cannot read latest submission upload file: #{file_path}"
      end
    end

    private

    def create_ontology
      params ||= @params

      # acronym must be well formed
      params['acronym'] = params['acronym'].upcase # coerce new ontologies to upper case

      # ontology acronym must be unique
      ont = Ontology.find(params['acronym']).first
      if ont.nil?
        ont = instance_from_params(Ontology, params)
      else
        error_msg = <<-ERR
        Ontology already exists, see #{ont.id}
        To add a new submission, POST to: /ontologies/#{params['acronym']}/submission.
        To modify the resource, use PATCH.
        ERR
        error 409, error_msg
      end

      # ontology name must be unique
      ont_names = Ontology.where.include(:name).to_a.map { |o| o.name }
      if ont_names.include?(ont.name)
        error 409, "Ontology name is already in use by another ontology."
      end

      if ont.valid?
        ont.save
      else
        error 422, ont.errors
      end

      reply 201, ont
    end

    namespace "/:acronym/admin" do

      get '/log' do
        ont = Ontology.find(params["acronym"]).first
        entries = []

        if ont
          ont.bring(:viewingRestriction)
          ont.bring(:administeredBy)
          ont.bring(:acl)
          check_access(ont)
          latest_any = ont.latest_submission(status: :any)

          if latest_any
            log_path = "#{LinkedData.settings.repository_folder}/#{NcboCron::Models::OntologiesReport.new.log_file(params["acronym"], latest_any.submissionId.to_s)}"

            if !log_path.empty? && File.file?(log_path)
              file = File.open(log_path, "rb")
              log_contents = file.read
              file.close

              severity_param = params['severity']&.split(',')&.map { |s| s.strip.upcase } # ['DEBUG', 'ERROR']
              entries = parse_log(log_contents, severity_param)
            end
          end
        end

        reply entries
      end

      private

      def parse_log(log_text, allowed_severities = nil)
        valid_severities = %w[ERROR DEBUG INFO]

        # Sanitize and validate allowed severities
        allowed = Array(allowed_severities).map(&:upcase) & valid_severities
        filter_enabled = !allowed.empty?

        entries = []

        log_text.each_line do |line|
          line.strip!

          # Match lines with timestamp
          match =
            line.match(/(?<level>[A-Z]), \[(?<timestamp>[^\]]+)\] +(?<severity>\w+) -- : (?<message>.+)/) ||
              # Match legacy format (no timestamp)
              line.match(/(?<severity>\w+) -- : (?<message>.+)/)

          next unless match

          entry = {
            level: match[:level] || 'I',
            timestamp: match.names.include?('timestamp') ? match[:timestamp].split('.').first : nil,
            severity: match[:severity],
            message: clean_message(match[:message])
          }

          entries << entry if !filter_enabled || allowed.include?(entry[:severity])
        end

        # Group by severity, sort within each group by timestamp DESC, then flatten in severity priority order
        valid_severities.flat_map do |sev|
          group = entries.select { |e| e[:severity] == sev }
          group.sort_by { |e| e[:timestamp] ? Time.parse(e[:timestamp]) : Time.at(0) }.reverse
        end
      end

      def clean_message(raw)
        raw
          .gsub(/\A\[\[?"?/, '')       # strip leading [[ or [" etc
          .gsub(/"?\]?\]?\z/, '')      # strip trailing ]]
          .gsub('\\n', "\n")           # replace \n (escaped) with real newline
          .gsub('\\t', "\t")           # replace \t (escaped) with real tab
          .strip
      end
    end
  end

  namespace "/ontologies_full" do
    ##
    # Display all ontologies with submissions and metrics
    get do
      resp = []
      onts = nil
      allow_views = params['also_include_views'] ||= false

      if allow_views
        onts = Ontology.where.include(Ontology.goo_attrs_to_load(includes_param)).to_a
      else
        onts = Ontology.where.filter(Goo::Filter.new(:viewOf).unbound).include(Ontology.goo_attrs_to_load(includes_param)).to_a
      end
      options = { also_include_views: allow_views, status: (params["include_status"] || "ANY") }
      subs = retrieve_latest_submissions(options)
      metrics_include = LinkedData::Models::Metric.goo_attrs_to_load(includes_param)
      LinkedData::Models::OntologySubmission.where.models(subs.values).include(metrics: metrics_include).all

      onts.each do |ont|
        sub = subs[ont.acronym]
        sub.ontology = nil if sub
        metrics = nil

        begin
          metrics = sub.nil? ? nil : sub.metrics
        rescue
          metrics = nil
        end

        resp << { ontology: ont, latest_submission: subs[ont.acronym], metrics: metrics }
      end

      reply resp
    end
  end
end
