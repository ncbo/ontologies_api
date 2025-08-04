class OntologySubmissionsController < ApplicationController
  get "/submissions" do
    check_last_modified_collection(LinkedData::Models::OntologySubmission)
    options = { also_include_views: params["also_include_views"], status: (params["include_status"] || "ANY") }
    reply retrieve_latest_submissions(options).values
  end

  ##
  # Create a new submission for an existing ontology
  post "/submissions" do
    ont = Ontology.find(uri_as_needed(params["ontology"])).include(Ontology.goo_attrs_to_load).first
    error 422, "You must provide a valid `acronym` to create a new submission" if ont.nil?
    reply 201, create_submission(ont)
  end

  namespace "/ontologies/:acronym/submissions" do

    ##
    # Display all submissions of an ontology
    get do
      ont = Ontology.find(params["acronym"]).include(:acronym, :administeredBy, :acl, :viewingRestriction).first
      error 422, "Ontology #{params["acronym"]} does not exist" unless ont
      check_last_modified_segment(LinkedData::Models::OntologySubmission, [ont.acronym])
      check_access(ont)
      options = {
        also_include_views: true,
        status: (params["include_status"] || "ANY"),
        ontology: params["acronym"]
      }
      subs = retrieve_submissions(options)

      reply subs.sort {|a,b| b.submissionId.to_i <=> a.submissionId.to_i }  # descending order of submissionId
    end

    # Create a new submission for an existing ontology
    post do
      ont = Ontology.find(params["acronym"]).include(Ontology.attributes).first
      error 422, "You must provide a valid `acronym` to create a new submission" if ont.nil?
      reply 201, create_submission(ont)
    end

    ##
    # Display a submission
    get '/:ontology_submission_id' do
      ont = Ontology.find(params["acronym"]).include(:acronym).first
      error 422, "Ontology #{params["acronym"]} does not exist" unless ont
      check_last_modified_segment(LinkedData::Models::OntologySubmission, [ont.acronym])
      ont.bring(:submissions)
      ont_submission = ont.submission(params["ontology_submission_id"])
      error 404, "`submissionId` not found" if ont_submission.nil?
      ont_submission.bring(*submission_include_params)
      reply ont_submission
    end

    ##
    # Update an existing submission of an ontology
    REQUIRES_REPROCESS = ["prefLabelProperty", "definitionProperty", "synonymProperty", "authorProperty", "classType", "hierarchyProperty", "obsoleteProperty", "obsoleteParent"]
    patch '/:ontology_submission_id' do
      ont = Ontology.find(params["acronym"]).first
      error 422, "You must provide an existing `acronym` to patch" if ont.nil?

      submission = ont.submission(params[:ontology_submission_id])
      error 422, "You must provide an existing `submissionId` to patch" if submission.nil?

      submission.bring(*OntologySubmission.attributes)
      populate_from_params(submission, params)
      add_file_to_submission(ont, submission)

      if submission.valid?
        submission.save
        if (params.keys & REQUIRES_REPROCESS).length > 0 || request_has_file?
          cron = NcboCron::Models::OntologySubmissionParser.new
          cron.queue_submission(submission, { all: true })
        end
      else
        error 422, submission.errors
      end

      halt 204
    end

    ##
    # Delete a specific ontology submission
    delete '/:ontology_submission_id' do
      ont = Ontology.find(params["acronym"]).first
      error 422, "You must provide an existing `acronym` to delete" if ont.nil?
      submission = ont.submission(params[:ontology_submission_id])
      error 422, "You must provide an existing `submissionId` to delete" if submission.nil?
      submission.delete
      halt 204
    end

    ##
    # Download a submission
    get '/:ontology_submission_id/download' do
      acronym = params["acronym"]
      submission_attributes = [:submissionId, :submissionStatus, :uploadFilePath, :pullLocation]
      included = Ontology.goo_attrs_to_load.concat([submissions: submission_attributes])
      ont = Ontology.find(acronym).include(included).first
      error 422, "You must provide an existing `acronym` to download" if ont.nil?
      ont.bring(:viewingRestriction) if ont.bring?(:viewingRestriction)
      check_access(ont)
      ont_restrict_downloads = LinkedData::OntologiesAPI.settings.restrict_download
      error 403, "License restrictions on download for #{acronym}" if ont_restrict_downloads.include? acronym
      submission = ont.submission(params['ontology_submission_id'].to_i)
      error 404, "There is no such submission for download" if submission.nil?
      file_path = submission.uploadFilePath
      # handle edge case where uploadFilePath is not set
      error 422, "Upload File Path is not set for this submission" if file_path.to_s.empty?
      download_format = params["download_format"].to_s.downcase
      allowed_formats = ["csv", "rdf"]
      if download_format.empty?
        file_path = submission.uploadFilePath
      elsif ([download_format] - allowed_formats).length > 0
        error 400, "Invalid download format: #{download_format}."
      elsif download_format.eql?("csv")
        if ont.latest_submission.id != submission.id
          error 400, "Invalid download format: #{download_format}."
        else
          latest_submission.bring(ontology: [:acronym])
          file_path = submission.csv_path
        end
      elsif download_format.eql?("rdf")
        file_path = submission.rdf_path
      end

      if File.readable? file_path
        send_file file_path, :filename => File.basename(file_path)
      else
        error 500, "Cannot read submission upload file: #{file_path}"
      end
    end

    ##
    # Download a submission diff file
    get '/:ontology_submission_id/download_diff' do
      acronym = params["acronym"]
      submission_attributes = [:submissionId, :submissionStatus, :diffFilePath]
      ont = Ontology.find(acronym).include(:submissions => submission_attributes).first
      error 422, "You must provide an existing `acronym` to download" if ont.nil?
      ont.bring(:viewingRestriction)
      check_access(ont)
      ont_restrict_downloads = LinkedData::OntologiesAPI.settings.restrict_download
      error 403, "License restrictions on download for #{acronym}" if ont_restrict_downloads.include? acronym
      submission = ont.submission(params['ontology_submission_id'].to_i)
      error 404, "There is no such submission for download" if submission.nil?
      file_path = submission.diffFilePath
      if File.readable? file_path
        send_file file_path, :filename => File.basename(file_path)
      else
        error 500, "Cannot read submission diff file: #{file_path}"
      end
    end

    def delete_submissions(startId, endId)
      startId.upto(endId + 1) do |i|
        sub = LinkedData::Models::OntologySubmission.find(RDF::URI.new("http://data.bioontology.org/ontologies/MS/submissions/#{i}")).first
        sub.delete if sub
      end
    end

  end

end
