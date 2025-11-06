require_relative '../test_case'
class TestOntologySubmissionsController < TestCase
  USERNAME = "test_user".freeze

  def before_all
    delete_ontologies_and_submissions
    super
  end

  def after_all
    delete_ontologies_and_submissions
    delete_user(USERNAME)
  end

  def setup
    delete_ontologies_and_submissions

    @suffix   = SecureRandom.hex(4)
    @acronym  = "TST#{@suffix}".upcase
    @name     = "Test Ontology #{@acronym}"
    @user = ensure_user(USERNAME)

    Ontology.new(acronym: @acronym, name: @name, administeredBy: [@user]).save

    test_file = File.expand_path("../../data/ontology_files/BRO_v3.1.owl", __FILE__)
    @file_params = {
      name: @name,
      hasOntologyLanguage: "OWL",
      administeredBy: USERNAME,
      "file" => Rack::Test::UploadedFile.new(test_file, ""),
      released: Time.now.utc.iso8601,
      contact: [{ name: "test_name", email: "test3@example.org" }],
      uri: "https://test.com/test",
      status: "production",
      description: "ontology description"
    }
  end

  def test_submissions_for_given_ontology
    num_onts_created, created_ont_acronyms = create_ontologies_and_submissions(ont_count: 1)
    ontology = created_ont_acronyms.first
    get "/ontologies/#{ontology}/submissions"
    assert last_response.ok?

    submissions_goo = OntologySubmission.where(ontology: { acronym: ontology}).to_a

    submissions = MultiJson.load(last_response.body)
    assert_equal submissions.length, submissions_goo.length
  end

  def test_create_new_submission_missing_file_and_pull_location
    post "/ontologies/#{@acronym}/submissions", name: @name, hasOntologyLanguage: "OWL"
    assert_equal(400, last_response.status, get_errors(last_response))
    assert MultiJson.load(last_response.body)["errors"]
  end

  def test_create_new_submission_file
    post "/ontologies/#{@acronym}/submissions", @file_params
    assert_equal(201, last_response.status, get_errors(last_response))
    sub = MultiJson.load(last_response.body)
    get "/ontologies/#{@acronym}"
    ont = MultiJson.load(last_response.body)
    assert_equal @acronym, ont["acronym"]
    # Cleanup
    delete "/ontologies/#{@acronym}/submissions/#{sub['submissionId']}"
    assert_equal(204, last_response.status, get_errors(last_response))
  end

  def test_create_new_ontology_submission
    post "/ontologies/#{@acronym}/submissions", @file_params
    assert_equal(201, last_response.status, get_errors(last_response))
    # Cleanup
    sub = MultiJson.load(last_response.body)
    delete "/ontologies/#{@acronym}/submissions/#{sub['submissionId']}"
    assert_equal(204, last_response.status, get_errors(last_response))
  end

  def test_patch_ontology_submission
    num_onts_created, created_ont_acronyms = create_ontologies_and_submissions(ont_count: 1)
    ont = Ontology.find(created_ont_acronyms.first).include(submissions: [:submissionId, ontology: :acronym]).first
    assert_operator ont.submissions.length, :>, 0
    submission = ont.submissions[0]
    new_values = {description: "Testing new description changes"}
    patch "/ontologies/#{submission.ontology.acronym}/submissions/#{submission.submissionId}", MultiJson.dump(new_values), "CONTENT_TYPE" => "application/json"
    assert_equal(204, last_response.status, get_errors(last_response))
    get "/ontologies/#{submission.ontology.acronym}/submissions/#{submission.submissionId}"
    submission = MultiJson.load(last_response.body)
    assert_equal "Testing new description changes", submission["description"]
  end

  def test_patch_submission_ignores_system_controlled_attributes
    _, acronyms = create_ontologies_and_submissions(ont_count: 1)
    acronym = acronyms.first
    ontology = Ontology.find(acronym).include(submissions: [:submissionId, ontology: :acronym]).first
    assert_operator ontology.submissions.length, :>, 0
    submission = ontology.submissions.first

    patch_payload = {
      description: "Updated description",
      uploadFilePath: "/malicious/path",
      diffFilePath: "/another/bad/path"
    }

    patch "/ontologies/#{acronym}/submissions/#{submission.submissionId}",
          MultiJson.dump(patch_payload),
          "CONTENT_TYPE" => "application/json"
    assert_equal 204, last_response.status

    get "/ontologies/#{acronym}/submissions/#{submission.submissionId}"
    updated_submission = MultiJson.load(last_response.body)

    # Confirm description was updated
    assert_equal "Updated description", updated_submission["description"]

    # Confirm restricted fields were ignored
    refute_includes updated_submission, "uploadFilePath"
    refute_includes updated_submission, "diffFilePath"
    refute_includes updated_submission, "missingImports"
  end

  def test_delete_ontology_submission
    num_onts_created, created_ont_acronyms = create_ontologies_and_submissions(ont_count: 1, random_submission_count: false, submission_count: 5)
    acronym = created_ont_acronyms.first
    submission_to_delete = (1..5).to_a.shuffle.first
    delete "/ontologies/#{acronym}/submissions/#{submission_to_delete}"
    assert_equal(204, last_response.status, get_errors(last_response))

    get "/ontologies/#{acronym}/submissions/#{submission_to_delete}"
    assert_equal(404, last_response.status, get_errors(last_response))
  end

  def test_delete_ontology_submissions
    submission_count = 5
    # Create a single ontology with 5 submissions
    num_onts_created, created_ont_acronyms = create_ontologies_and_submissions(
      ont_count: 1,
      random_submission_count: false,
      submission_count: submission_count
    )
    acronym = created_ont_acronyms.first
    all_ids = (1..submission_count).to_a
    delete_ids = all_ids.first(3)
    keep_ids = (all_ids - delete_ids).sort
    assert_equal submission_count - delete_ids.size, keep_ids.size, "Unexpected keep_ids size"

    # Kick off the long-running bulk delete via the collection DELETE endpoint
    payload = MultiJson.dump({ ontology_submission_ids: delete_ids })
    delete "/ontologies/#{acronym}/submissions", payload, "CONTENT_TYPE" => "application/json"

    assert_equal(202, last_response.status, get_errors(last_response))
    body = MultiJson.load(last_response.body)
    process_id = body["process_id"]
    assert process_id, "Expected process_id in response for bulk delete"

    # Poll the bulk_delete status endpoint until it's done (or timeout)
    max_attempts = 100
    attempts = 0
    status_payload = nil

    loop do
      get "/ontologies/#{acronym}/submissions/bulk_delete/#{process_id}"
      assert_equal(200, last_response.status, get_errors(last_response))
      status_payload = MultiJson.load(last_response.body)

      status = status_payload.is_a?(Hash) ? status_payload["status"] : nil
      has_errors = status_payload.is_a?(Hash) && status_payload["errors"]
      break if status == "done" || has_errors

      attempts += 1
      assert attempts < max_attempts, "Timed out waiting for bulk delete to finish"
      sleep 0.1
    end

     # Validate result payload
    if status_payload["errors"]
      flunk "Bulk delete returned errors: #{status_payload['errors'].inspect}"
    else
      returned_deleted = Array(status_payload["deleted_ids"]).map(&:to_i).sort
      assert_equal(delete_ids, returned_deleted, "Deleted IDs mismatch")
      assert_equal(delete_ids.size, status_payload["deleted_count"], "Deleted count mismatch")
      assert(status_payload["missing_ids"].nil? || status_payload["missing_ids"].empty?, "Expected no missing IDs")
    end

    # Deleted ones should be gone
    delete_ids.each do |sid|
      get "/ontologies/#{acronym}/submissions/#{sid}"
      assert_equal(404, last_response.status, "Submission #{sid} should be gone, but GET returned #{last_response.status} for #{sid}")
    end

    # Kept ones should still be present
    keep_ids.each do |sid|
      get "/ontologies/#{acronym}/submissions/#{sid}"
      assert(last_response.ok?, "Submission #{sid} should still exist, but GET returned #{last_response.status}")
    end
  end

  def test_download_submission
    num_onts_created, created_ont_acronyms, onts = create_ontologies_and_submissions(ont_count: 1, submission_count: 1, process_submission: false)
    assert_equal(1, num_onts_created, msg="Failed to create 1 ontology?")
    assert_equal(1, onts.length, msg="Failed to create 1 ontology?")
    ont = onts.first
    ont.bring(:submissions, :acronym)
    assert_instance_of(Ontology, ont, "ont is not a #{Ontology.class}")
    assert_equal(1, ont.submissions.length, "Failed to create 1 ontology submission?")
    sub = ont.submissions.first
    sub.bring(:submissionId)
    assert_instance_of(OntologySubmission, sub, "sub is not a #{OntologySubmission.class}")
    # Clear restrictions on downloads
    LinkedData::OntologiesAPI.settings.restrict_download = []
    # Download the specific submission
    get "/ontologies/#{ont.acronym}/submissions/#{sub.submissionId}/download"
    assert_equal(200, last_response.status, 'failed download for specific submission : ' + get_errors(last_response))
    # Add restriction on download
    acronym = created_ont_acronyms.first
    LinkedData::OntologiesAPI.settings.restrict_download = [acronym]
    # Try download
    get "/ontologies/#{ont.acronym}/submissions/#{sub.submissionId}/download"
    # download should fail with a 403 status
    assert_equal(403, last_response.status, 'failed to restrict download for ontology : ' + get_errors(last_response))
    # Clear restrictions on downloads
    LinkedData::OntologiesAPI.settings.restrict_download = []
    # see also test_ontologies_controller::test_download_ontology

    # Test downloads of nonexistent ontology
    get "/ontologies/BOGUS66/submissions/55/download"
    assert_equal(422, last_response.status, "failed to handle downloads of nonexistent ontology" + get_errors(last_response))
  end

  def test_download_ontology_submission_rdf
    count, created_ont_acronyms, onts = create_ontologies_and_submissions(ont_count: 1, submission_count: 1, process_submission: true)
    acronym = created_ont_acronyms.first
    ont = onts.first
    sub = ont.submissions.first

    get "/ontologies/#{acronym}/submissions/#{sub.submissionId}/download?download_format=rdf"
    assert_equal(200, last_response.status, "Download failure for '#{acronym}' ontology: " + get_errors(last_response))

    # Download should fail with a 400 status.
    get "/ontologies/#{acronym}/submissions/#{sub.submissionId}/download?download_format=csr"
    assert_equal(400, last_response.status, "Download failure for '#{acronym}' ontology: " + get_errors(last_response))
  end

  def test_download_acl_only
    count, created_ont_acronyms, onts = create_ontologies_and_submissions(ont_count: 1, submission_count: 1, process_submission: false)
    acronym = created_ont_acronyms.first
    ont = onts.first.bring_remaining
    ont.bring(:submissions)
    sub = ont.submissions.first
    sub.bring(:submissionId)

    begin
      allowed_user = User.new({
        username: "allowed",
        email: "test4@example.org",
        password: "12345"
      })
      allowed_user.save
      blocked_user = User.new({
        username: "blocked",
        email: "test5@example.org",
        password: "12345"
      })
      blocked_user.save

      ont.acl = [allowed_user]
      ont.viewingRestriction = "private"
      ont.save

      LinkedData.settings.enable_security = true

      get "/ontologies/#{acronym}/submissions/#{sub.submissionId}/download?apikey=#{allowed_user.apikey}"
      assert_equal(200, last_response.status, "User who is in ACL couldn't download ontology")

      get "/ontologies/#{acronym}/submissions/#{sub.submissionId}/download?apikey=#{blocked_user.apikey}"
      assert_equal(403, last_response.status, "User who isn't in ACL could download ontology")

      admin = ont.administeredBy.first
      admin.bring(:apikey)
      get "/ontologies/#{acronym}/submissions/#{sub.submissionId}/download?apikey=#{admin.apikey}"
      assert_equal(200, last_response.status, "Admin couldn't download ontology")
    ensure
      LinkedData.settings.enable_security = false
      del = User.find("allowed").first
      del.delete if del
      del = User.find("blocked").first
      del.delete if del
    end
  end

  def test_submissions_default_includes
    ontology_count = 5
    num_onts_created, created_ont_acronyms, ontologies = create_ontologies_and_submissions(ont_count: ontology_count, submission_count: 1, submissions_to_process: [])

    submission_default_attributes = LinkedData::Models::OntologySubmission.hypermedia_settings[:serialize_default].map(&:to_s)

    get("/submissions?display_links=false&display_context=false&include_status=ANY")
    assert(last_response.ok?)
    submissions = MultiJson.load(last_response.body)

    assert_equal ontology_count, submissions.size
    submissions.each do |sub|
      assert_equal(submission_default_attributes, submission_keys(sub))
    end

    get("/ontologies/#{created_ont_acronyms.first}/submissions?display_links=false&display_context=false")

    assert last_response.ok?
    submissions = MultiJson.load(last_response.body)
    assert_equal(1, submissions.size)
    submissions.each do |sub|
      assert_equal(submission_default_attributes.sort, submission_keys(sub).sort)
    end
  end

  def test_submissions_all_includes
    ontology_count = 5
    num_onts_created, created_ont_acronyms, ontologies = create_ontologies_and_submissions(ont_count: ontology_count, submission_count: 1, submissions_to_process: [])
    def submission_all_attributes
      attrs = OntologySubmission.goo_attrs_to_load([:all])
      embed_attrs = attrs.select { |x| x.is_a?(Hash) }.first

      attrs.delete_if { |x| x.is_a?(Hash) }.map(&:to_s) + embed_attrs.keys.map(&:to_s)
    end
    get("/submissions?include=all&display_links=false&display_context=false")

    assert(last_response.ok?)
    submissions = MultiJson.load(last_response.body)
    assert_equal(ontology_count, submissions.size)

    submissions.each do |sub|
      assert_equal(submission_all_attributes.sort, submission_keys(sub).sort)
      assert_submission_contact_structure(sub)
    end

    get("/ontologies/#{created_ont_acronyms.first}/submissions?include=all&display_links=false&display_context=false")

    assert(last_response.ok?)
    submissions = MultiJson.load(last_response.body)
    assert_equal(1, submissions.size)

    submissions.each do |sub|
      assert_equal(submission_all_attributes.sort, submission_keys(sub).sort)
      assert_submission_contact_structure(sub)
    end

    get("/ontologies/#{created_ont_acronyms.first}/latest_submission?include=all&display_links=false&display_context=false")
    assert(last_response.ok?)
    sub = MultiJson.load(last_response.body)

    assert_equal(submission_all_attributes.sort, submission_keys(sub).sort)
    assert_submission_contact_structure(sub)

    get("/ontologies/#{created_ont_acronyms.first}/submissions/1?include=all&display_links=false&display_context=false")
    assert(last_response.ok?)
    sub = MultiJson.load(last_response.body)

    assert_equal(submission_all_attributes.sort, submission_keys(sub).sort)
    assert_submission_contact_structure(sub)
  end

  def test_submissions_custom_includes
    ontology_count = 5
    num_onts_created, created_ont_acronyms, ontologies = create_ontologies_and_submissions(ont_count: ontology_count, submission_count: 1, submissions_to_process: [])
    include = 'ontology,contact,submissionId'

    get("/submissions?include=#{include}&display_links=false&display_context=false")

    assert(last_response.ok?)
    submissions = MultiJson.load(last_response.body)
    assert_equal ontology_count, submissions.size
    submissions.each do |sub|
      assert_equal(include.split(','), submission_keys(sub))
      assert_submission_contact_structure(sub)
    end

    get("/ontologies/#{created_ont_acronyms.first}/submissions?include=#{include}&display_links=false&display_context=false")

    assert(last_response.ok?)
    submissions = MultiJson.load(last_response.body)
    assert_equal(1, submissions.size)
    submissions.each do |sub|
      assert_equal(include.split(','), submission_keys(sub))
      assert_submission_contact_structure(sub)
    end

    get("/ontologies/#{created_ont_acronyms.first}/latest_submission?include=#{include}&display_links=false&display_context=false")
    assert(last_response.ok?)
    sub = MultiJson.load(last_response.body)
    assert_equal(include.split(','), submission_keys(sub))
    assert_submission_contact_structure(sub)

    get("/ontologies/#{created_ont_acronyms.first}/submissions/1?include=#{include}&display_links=false&display_context=false")
    assert(last_response.ok?)
    sub = MultiJson.load(last_response.body)
    assert_equal(include.split(','), submission_keys(sub))
    assert_submission_contact_structure(sub)
  end

  private
  def submission_keys(sub)
    sub.to_hash.keys - %w[@id @type id]
  end

  def assert_submission_contact_structure(sub)
    assert sub["contact"], "Contact should be present"
    if sub["contact"].first
      assert_equal(%w[name email id].sort, sub["contact"].first.keys.sort)
    end
  end

end
