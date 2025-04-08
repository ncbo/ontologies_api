require_relative '../test_case'
class TestOntologySubmissionsController < TestCase

  def before_suite
    self.backend_4s_delete
    self.class._set_vars
    self.class._create_user
    self.class._create_onts
  end

  def self._set_vars
    @@acronym = "TST"
    @@name = "Test Ontology"
    @@test_file = File.expand_path("../../data/ontology_files/BRO_v3.1.owl", __FILE__)
    @@file_params = {
      name: @@name,
      hasOntologyLanguage: "OWL",
      administeredBy: "tim",
      "file" => Rack::Test::UploadedFile.new(@@test_file, ""),
      released: DateTime.now.to_s,
      contact: [{name: "test_name", email: "test3@example.org"}],
      uri: 'https://test.com/test',
      status: 'production',
      description: 'ontology description'
    }
    @@status_uploaded = "UPLOADED"
    @@status_rdf = "RDF"
  end

  def self._create_user
    username = "tim"
    test_user = User.new(username: username, email: "#{username}@example.org", password: "password")
    test_user.save if test_user.valid?
    @@user = test_user.valid? ? test_user : User.find(username).first
  end

  def self._create_onts
    ont = Ontology.new(acronym: @@acronym, name: @@name, administeredBy: [@@user])
    ont.save
  end

  def setup
    delete_ontologies_and_submissions
    ont = Ontology.new(acronym: @@acronym, name: @@name, administeredBy: [@@user])
    ont.save
  end


  def test_submissions_for_given_ontology
    num_onts_created, created_ont_acronyms = create_ontologies_and_submissions(ont_count: 1)
    ontology = created_ont_acronyms.first
    get "/ontologies/#{ontology}/submissions"
    assert last_response.ok?

    submissions_goo = OntologySubmission.where(ontology: { acronym: ontology}).to_a

    submissions = MultiJson.load(last_response.body)
    assert submissions.length == submissions_goo.length
  end

  def test_create_new_submission_missing_file_and_pull_location
    post "/ontologies/#{@@acronym}/submissions", name: @@name, hasOntologyLanguage: "OWL"
    assert_equal(400, last_response.status, msg=get_errors(last_response))
    assert MultiJson.load(last_response.body)["errors"]
  end

  def test_create_new_submission_file
    post "/ontologies/#{@@acronym}/submissions", @@file_params
    assert_equal(201, last_response.status, msg=get_errors(last_response))
    sub = MultiJson.load(last_response.body)
    get "/ontologies/#{@@acronym}"
    ont = MultiJson.load(last_response.body)
    assert ont["acronym"].eql?(@@acronym)
    # Cleanup
    delete "/ontologies/#{@@acronym}/submissions/#{sub['submissionId']}"
    assert_equal(204, last_response.status, msg=get_errors(last_response))
  end

  def test_create_new_ontology_submission
    post "/ontologies/#{@@acronym}/submissions", @@file_params
    assert_equal(201, last_response.status, msg=get_errors(last_response))
    # Cleanup
    sub = MultiJson.load(last_response.body)
    delete "/ontologies/#{@@acronym}/submissions/#{sub['submissionId']}"
    assert_equal(204, last_response.status, msg=get_errors(last_response))
  end

  def test_patch_ontology_submission
    num_onts_created, created_ont_acronyms = create_ontologies_and_submissions(ont_count: 1)
    ont = Ontology.find(created_ont_acronyms.first).include(submissions: [:submissionId, ontology: :acronym]).first
    assert(ont.submissions.length > 0)
    submission = ont.submissions[0]
    new_values = {description: "Testing new description changes"}
    patch "/ontologies/#{submission.ontology.acronym}/submissions/#{submission.submissionId}", MultiJson.dump(new_values), "CONTENT_TYPE" => "application/json"
    assert_equal(204, last_response.status, msg=get_errors(last_response))
    get "/ontologies/#{submission.ontology.acronym}/submissions/#{submission.submissionId}"
    submission = MultiJson.load(last_response.body)
    assert submission["description"].eql?("Testing new description changes")
  end

  def test_reject_system_controlled_submission_attributes_on_post
    bad_params = @@file_params.merge({
      uploadFilePath: "/should/not/be/allowed",
      diffFilePath: "/also/not/allowed"
    })

    post "/ontologies/#{@@acronym}/submissions", bad_params
    assert_equal(400, last_response.status, msg=get_errors(last_response))

    body = MultiJson.load(last_response.body)
    assert_includes body["errors"].join, "uploadFilePath"
    assert_includes body["errors"].join, "diffFilePath"
  end

  def test_delete_ontology_submission
    num_onts_created, created_ont_acronyms = create_ontologies_and_submissions(ont_count: 1, random_submission_count: false, submission_count: 5)
    acronym = created_ont_acronyms.first
    submission_to_delete = (1..5).to_a.shuffle.first
    delete "/ontologies/#{acronym}/submissions/#{submission_to_delete}"
    assert_equal(204, last_response.status, msg=get_errors(last_response))

    get "/ontologies/#{acronym}/submissions/#{submission_to_delete}"
    assert_equal(404, last_response.status, msg=get_errors(last_response))
  end

  def test_download_submission
    num_onts_created, created_ont_acronyms, onts = create_ontologies_and_submissions(ont_count: 1, submission_count: 1, process_submission: false)
    assert_equal(1, num_onts_created, msg="Failed to create 1 ontology?")
    assert_equal(1, onts.length, msg="Failed to create 1 ontology?")
    ont = onts.first
    ont.bring(:submissions, :acronym)
    assert_instance_of(Ontology, ont, msg="ont is not a #{Ontology.class}")
    assert_equal(1, ont.submissions.length, msg="Failed to create 1 ontology submission?")
    sub = ont.submissions.first
    sub.bring(:submissionId)
    assert_instance_of(OntologySubmission, sub, msg="sub is not a #{OntologySubmission.class}")
    # Clear restrictions on downloads
    LinkedData::OntologiesAPI.settings.restrict_download = []
    # Download the specific submission
    get "/ontologies/#{ont.acronym}/submissions/#{sub.submissionId}/download"
    assert_equal(200, last_response.status, msg='failed download for specific submission : ' + get_errors(last_response))
    # Add restriction on download
    acronym = created_ont_acronyms.first
    LinkedData::OntologiesAPI.settings.restrict_download = [acronym]
    # Try download
    get "/ontologies/#{ont.acronym}/submissions/#{sub.submissionId}/download"
    # download should fail with a 403 status
    assert_equal(403, last_response.status, msg='failed to restrict download for ontology : ' + get_errors(last_response))
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
    assert_equal(200, last_response.status, msg="Download failure for '#{acronym}' ontology: " + get_errors(last_response))

    # Download should fail with a 400 status.
    get "/ontologies/#{acronym}/submissions/#{sub.submissionId}/download?download_format=csr"
    assert_equal(400, last_response.status, msg="Download failure for '#{acronym}' ontology: " + get_errors(last_response))
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
      assert_equal(200, last_response.status, msg="User who is in ACL couldn't download ontology")

      get "/ontologies/#{acronym}/submissions/#{sub.submissionId}/download?apikey=#{blocked_user.apikey}"
      assert_equal(403, last_response.status, msg="User who isn't in ACL could download ontology")

      admin = ont.administeredBy.first
      admin.bring(:apikey)
      get "/ontologies/#{acronym}/submissions/#{sub.submissionId}/download?apikey=#{admin.apikey}"
      assert_equal(200, last_response.status, msg="Admin couldn't download ontology")
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
    assert last_response.ok?
    submissions = MultiJson.load(last_response.body)

    assert_equal ontology_count, submissions.size
    assert(submissions.all? { |sub| submission_default_attributes.eql?(submission_keys(sub)) })

    get("/ontologies/#{created_ont_acronyms.first}/submissions?display_links=false&display_context=false")

    assert last_response.ok?
    submissions = MultiJson.load(last_response.body)
    assert_equal 1, submissions.size
    assert(submissions.all? { |sub| submission_default_attributes.eql?(submission_keys(sub)) })
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

    assert last_response.ok?
    submissions = MultiJson.load(last_response.body)
    assert_equal ontology_count, submissions.size

    assert(submissions.all? { |sub| submission_all_attributes.sort.eql?(submission_keys(sub).sort) })
    assert(submissions.all? { |sub| sub["contact"] && (sub["contact"].first.nil? || sub["contact"].first.keys.eql?(%w[name email id])) })

    get("/ontologies/#{created_ont_acronyms.first}/submissions?include=all&display_links=false&display_context=false")

    assert last_response.ok?
    submissions = MultiJson.load(last_response.body)
    assert_equal 1, submissions.size

    assert(submissions.all? { |sub| submission_all_attributes.sort.eql?(submission_keys(sub).sort) })
    assert(submissions.all? { |sub| sub["contact"] && (sub["contact"].first.nil? || sub["contact"].first.keys.eql?(%w[name email id])) })

    get("/ontologies/#{created_ont_acronyms.first}/latest_submission?include=all&display_links=false&display_context=false")
    assert last_response.ok?
    sub = MultiJson.load(last_response.body)

    assert(submission_all_attributes.sort.eql?(submission_keys(sub).sort))
    assert(sub["contact"] && (sub["contact"].first.nil? || sub["contact"].first.keys.eql?(%w[name email id])))

    get("/ontologies/#{created_ont_acronyms.first}/submissions/1?include=all&display_links=false&display_context=false")
    assert last_response.ok?
    sub = MultiJson.load(last_response.body)

    assert(submission_all_attributes.sort.eql?(submission_keys(sub).sort))
    assert(sub["contact"] && (sub["contact"].first.nil? || sub["contact"].first.keys.eql?(%w[name email id])))
  end

  def test_submissions_custom_includes
    ontology_count = 5
    num_onts_created, created_ont_acronyms, ontologies = create_ontologies_and_submissions(ont_count: ontology_count, submission_count: 1, submissions_to_process: [])
    include = 'ontology,contact,submissionId'

    get("/submissions?include=#{include}&display_links=false&display_context=false")

    assert last_response.ok?
    submissions = MultiJson.load(last_response.body)
    assert_equal ontology_count, submissions.size
    assert(submissions.all? { |sub| include.split(',').eql?(submission_keys(sub)) })
    assert(submissions.all? { |sub| sub["contact"] && (sub["contact"].first.nil? || sub["contact"].first.keys.eql?(%w[name email id])) })

    get("/ontologies/#{created_ont_acronyms.first}/submissions?include=#{include}&display_links=false&display_context=false")

    assert last_response.ok?
    submissions = MultiJson.load(last_response.body)
    assert_equal 1, submissions.size
    assert(submissions.all? { |sub| include.split(',').eql?(submission_keys(sub)) })
    assert(submissions.all? { |sub| sub["contact"] && (sub["contact"].first.nil? || sub["contact"].first.keys.eql?(%w[name email id])) })

    get("/ontologies/#{created_ont_acronyms.first}/latest_submission?include=#{include}&display_links=false&display_context=false")
    assert last_response.ok?
    sub = MultiJson.load(last_response.body)
    assert(include.split(',').eql?(submission_keys(sub)))
    assert(sub["contact"] && (sub["contact"].first.nil? || sub["contact"].first.keys.eql?(%w[name email id])))

    get("/ontologies/#{created_ont_acronyms.first}/submissions/1?include=#{include}&display_links=false&display_context=false")
    assert last_response.ok?
    sub = MultiJson.load(last_response.body)
    assert(include.split(',').eql?(submission_keys(sub)))
    assert(sub["contact"] && (sub["contact"].first.nil? || sub["contact"].first.keys.eql?(%w[name email id])))
  end

  private
  def submission_keys(sub)
    sub.to_hash.keys - %w[@id @type id]
  end

end
