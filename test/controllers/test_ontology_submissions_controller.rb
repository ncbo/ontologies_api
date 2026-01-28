require_relative "../test_case"
class TestOntologySubmissionsController < TestCase
  def after_all
    delete_ontologies_and_submissions
  end

  def setup
    delete_ontologies_and_submissions

    @suffix = SecureRandom.hex(4)
    @acronym = "TST#{@suffix}".upcase
    @name = "Test Ontology #{@acronym}"
    @test_user, _format, _contact = LinkedData::SampleData::Ontology.ontology_objects

    Ontology.new(acronym: @acronym, name: @name, administeredBy: [@test_user]).save

    test_file = File.expand_path("../data/ontology_files/BRO_v3.1.owl", __dir__)
    @file_params = {
      name: @name,
      hasOntologyLanguage: "OWL",
      administeredBy: @test_user,
      file: Rack::Test::UploadedFile.new(test_file, ""),
      released: Time.now.utc.iso8601,
      contact: [{name: "test_name", email: "test3@example.org"}],
      uri: "https://test.com/test",
      status: "production",
      description: "ontology description"
    }
  end

  def test_submissions_for_given_ontology
    _, created_ont_acronyms = create_ontologies_and_submissions(ont_count: 1)
    ontology = created_ont_acronyms.first
    get "/ontologies/#{ontology}/submissions"
    assert last_response.ok?

    submissions_goo = OntologySubmission.where(ontology: {acronym: ontology}).to_a

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
    delete "/ontologies/#{@acronym}/submissions/#{sub["submissionId"]}"
    assert_equal(204, last_response.status, get_errors(last_response))
  end

  def test_create_new_ontology_submission
    post "/ontologies/#{@acronym}/submissions", @file_params
    assert_equal(201, last_response.status, get_errors(last_response))
    # Cleanup
    sub = MultiJson.load(last_response.body)
    delete "/ontologies/#{@acronym}/submissions/#{sub["submissionId"]}"
    assert_equal(204, last_response.status, get_errors(last_response))
  end

  def test_patch_ontology_submission
    _, created_ont_acronyms = create_ontologies_and_submissions(ont_count: 1)
    ont = Ontology.find(created_ont_acronyms.first).include(submissions: [:submissionId, {ontology: :acronym}]).first
    assert_operator ont.submissions.length, :>, 0
    submission = ont.submissions[0]
    new_values = {description: "Testing new description changes"}
    patch "/ontologies/#{submission.ontology.acronym}/submissions/#{submission.submissionId}",
      MultiJson.dump(new_values), "CONTENT_TYPE" => "application/json"
    assert_equal(204, last_response.status, get_errors(last_response))
    get "/ontologies/#{submission.ontology.acronym}/submissions/#{submission.submissionId}"
    submission = MultiJson.load(last_response.body)
    assert_equal "Testing new description changes", submission["description"]
  end

  def test_patch_submission_ignores_system_controlled_attributes
    _, acronyms = create_ontologies_and_submissions(ont_count: 1)
    acronym = acronyms.first
    ontology = Ontology.find(acronym).include(submissions: [:submissionId, {ontology: :acronym}]).first
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
    assert_equal(204, last_response.status, get_errors(last_response))

    get "/ontologies/#{acronym}/submissions/#{submission.submissionId}"
    updated_submission = MultiJson.load(last_response.body)

    # Confirm description was updated
    assert_equal("Updated description", updated_submission["description"])

    # Confirm restricted fields were ignored
    refute_includes(updated_submission, "uploadFilePath")
    refute_includes(updated_submission, "diffFilePath")
    refute_includes(updated_submission, "missingImports")
  end

  def test_delete_ontology_submission
    _, created_ont_acronyms = create_ontologies_and_submissions(ont_count: 1,
      random_submission_count: false, submission_count: 5)
    acronym = created_ont_acronyms.first
    submission_to_delete = (1..5).to_a.sample
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
    payload = MultiJson.dump({ontology_submission_ids: delete_ids})
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
      flunk "Bulk delete returned errors: #{status_payload["errors"].inspect}"
    else
      returned_deleted = Array(status_payload["deleted_ids"]).map(&:to_i).sort
      assert_equal(delete_ids, returned_deleted, "Deleted IDs mismatch")
      assert_equal(delete_ids.size, status_payload["deleted_count"], "Deleted count mismatch")
      assert(status_payload["missing_ids"].nil? || status_payload["missing_ids"].empty?, "Expected no missing IDs")
    end

    # Deleted ones should be gone
    delete_ids.each do |sid|
      get "/ontologies/#{acronym}/submissions/#{sid}"
      assert_equal(404, last_response.status,
        "Submission #{sid} should be gone, but GET returned #{last_response.status} for #{sid}")
    end

    # Kept ones should still be present
    keep_ids.each do |sid|
      get "/ontologies/#{acronym}/submissions/#{sid}"
      assert(last_response.ok?, "Submission #{sid} should still exist, but GET returned #{last_response.status}")
    end
  end

  def test_download_submission
    num_onts_created, created_ont_acronyms, onts = create_ontologies_and_submissions(ont_count: 1, submission_count: 1,
      process_submission: false)
    assert_equal(1, num_onts_created, "Failed to create 1 ontology?")
    assert_equal(1, onts.length, "Failed to create 1 ontology?")
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
    assert_equal(200, last_response.status, "failed download for specific submission : " + get_errors(last_response))
    # Add restriction on download
    acronym = created_ont_acronyms.first
    LinkedData::OntologiesAPI.settings.restrict_download = [acronym]
    # Try download
    get "/ontologies/#{ont.acronym}/submissions/#{sub.submissionId}/download"
    # download should fail with a 403 status
    assert_equal(403, last_response.status, "failed to restrict download for ontology : " + get_errors(last_response))
    # Clear restrictions on downloads
    LinkedData::OntologiesAPI.settings.restrict_download = []
    # see also test_ontologies_controller::test_download_ontology

    # Test downloads of nonexistent ontology
    get '/ontologies/BOGUS66/submissions/55/download'
    assert_equal(422, last_response.status,
      "failed to handle downloads of nonexistent ontology" + get_errors(last_response))
  end

  def test_download_ontology_submission_rdf
    _, created_ont_acronyms, onts = create_ontologies_and_submissions(ont_count: 1, submission_count: 1,
      process_submission: true)
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
    _, created_ont_acronyms, onts = create_ontologies_and_submissions(ont_count: 1, submission_count: 1,
      process_submission: false)
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
    _, created_ont_acronyms, ontologies = create_ontologies_and_submissions(ont_count: ontology_count,
      submission_count: 1, submissions_to_process: [])

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
    _, created_ont_acronyms, = create_ontologies_and_submissions(ont_count: ontology_count, submission_count: 1, submissions_to_process: [])

    submission_all_attributes = begin
                                  attrs = OntologySubmission.goo_attrs_to_load([:all])
                                  embed_attrs = attrs.select { |x| x.is_a?(Hash) }.first || {}
                                  attrs.reject { |x| x.is_a?(Hash) }.map(&:to_s) + embed_attrs.keys.map(&:to_s)
                                end.sort

    params = '?include=all&display_links=false&display_context=false'

    [
      "/submissions#{params}",
      "/ontologies/#{created_ont_acronyms.first}/submissions#{params}",
      "/ontologies/#{created_ont_acronyms.first}/latest_submission#{params}",
      "/ontologies/#{created_ont_acronyms.first}/submissions/1#{params}"
    ].each do |url|
      get(url)
      assert last_response.ok?

      response_body = MultiJson.load(last_response.body)
      submissions = response_body.is_a?(Array) ? response_body : [response_body]

      assert_equal(ontology_count, submissions.size) if url == "/submissions#{params}"
      assert(submissions.all? { |sub| submission_all_attributes.eql?(submission_keys(sub).sort) })
      assert(submissions.all? { |sub| sub['contact']&.first&.keys.to_a.sort.eql?(%w[name email id].sort) })
    end
  end

  def test_submissions_custom_includes
    ontology_count = 5
    _, created_ont_acronyms, _ = create_ontologies_and_submissions(ont_count: ontology_count, submission_count: 1, submissions_to_process: [])
    include_keys = %w[ontology contact submissionId]
    params = "?include=#{include_keys.join(',')}&display_links=false&display_context=false"

    [
      "/submissions#{params}",
      "/ontologies/#{created_ont_acronyms.first}/submissions#{params}",
      "/ontologies/#{created_ont_acronyms.first}/latest_submission#{params}",
      "/ontologies/#{created_ont_acronyms.first}/submissions/1#{params}"
    ].each do |url|
      get(url)
      assert last_response.ok?

      response_body = MultiJson.load(last_response.body)
      submissions = response_body.is_a?(Array) ? response_body : [response_body]

      assert_equal(ontology_count, submissions.size) if url == "/submissions#{params}"
      assert(submissions.all? { |sub| include_keys.eql?(submission_keys(sub)) })
      assert(submissions.all? { |sub| sub['contact']&.first&.keys&.sort.eql?(%w[name email id].sort) })
    end
  end

  def test_ontology_submissions_access_controller
    _, created_ont_acronyms, onts = create_ontologies_and_submissions(ont_count: 2, submission_count: 1, process_submission: false)
    # case first submission is private
    created_ont_acronyms.first
    ont = onts.first.bring_remaining

    begin
      allowed_user = User.new({
                                username: 'allowed',
                                email: 'test@example.org',
                                password: '12345'
                              })
      allowed_user.save
      blocked_user = User.new({
                                username: 'blocked',
                                email: 'test1254@example.org',
                                password: '12345'
                              })
      blocked_user.save

      ont.acl = [allowed_user]
      ont.viewingRestriction = 'private'
      ont.save

      LinkedData.settings.enable_security = true

      get "/submissions?apikey=#{allowed_user.apikey}"
      assert_equal 200, last_response.status
      submissions = MultiJson.load(last_response.body)
      assert_equal 2, submissions.size

      get "/submissions?apikey=#{blocked_user.apikey}"
      assert_equal 200, last_response.status
      submissions = MultiJson.load(last_response.body)
      assert_equal 1, submissions.size
    ensure
      LinkedData.settings.enable_security = false
      del = User.find('allowed').first
      del.delete if del
      del = User.find('blocked').first
      del.delete if del
    end
  end

  def test_submissions_pagination
    create_ontologies_and_submissions(ont_count: 2, submission_count: 2)

    get '/submissions'
    assert last_response.ok?
    submissions = MultiJson.load(last_response.body)

    assert_equal 2, submissions.length

    get '/submissions?page=1&pagesize=1'
    assert last_response.ok?
    submissions = MultiJson.load(last_response.body)
    assert_equal 1, submissions['collection'].length
  end

  def test_submissions_pagination_filter
    num_onts_created, created_ont_acronyms, ontologies = create_ontologies_and_submissions(ont_count: 10, submission_count: 1)
    group1 = LinkedData::Models::Group.new(acronym: 'group-1', name: 'Test Group 1').save
    group2 = LinkedData::Models::Group.new(acronym: 'group-2', name: 'Test Group 2').save
    category1 = LinkedData::Models::Category.new(acronym: 'category-1', name: 'Test Category 1').save
    category2 = LinkedData::Models::Category.new(acronym: 'category-2', name: 'Test Category 2').save

    ontologies1 = ontologies[0..5].each do |o|
      o.bring_remaining
      o.group = [group1]
      o.hasDomain = [category1]
      o.save
    end

    ontologies2 = ontologies[6..8].each do |o|
      o.bring_remaining
      o.group = [group2]
      o.hasDomain = [category2]
      o.save
    end

    # test filter by group and category
    get "/submissions?page=1&pagesize=100&group=#{group1.acronym}"
    assert last_response.ok?
    assert_equal ontologies1.size, MultiJson.load(last_response.body)['collection'].length
    get "/submissions?page=1&pagesize=100&group=#{group2.acronym}"
    assert last_response.ok?
    assert_equal ontologies2.size, MultiJson.load(last_response.body)['collection'].length
    get "/submissions?page=1&pagesize=100&hasDomain=#{category1.acronym}"
    assert last_response.ok?
    assert_equal ontologies1.size, MultiJson.load(last_response.body)['collection'].length
    get "/submissions?page=1&pagesize=100&hasDomain=#{category2.acronym}"
    assert last_response.ok?
    assert_equal ontologies2.size, MultiJson.load(last_response.body)['collection'].length
    get "/submissions?page=1&pagesize=100&hasDomain=#{category2.acronym}&group=#{group1.acronym}"
    assert last_response.ok?
    assert_equal 0, MultiJson.load(last_response.body)['collection'].length
    get "/submissions?page=1&pagesize=100&hasDomain=#{category2.acronym}&group=#{group2.acronym}"
    assert last_response.ok?
    assert_equal ontologies2.size, MultiJson.load(last_response.body)['collection'].length

    ontologies3 = ontologies[9]
    ontologies3.bring_remaining
    ontologies3.group = [group1, group2]
    ontologies3.hasDomain = [category1, category2]
    ontologies3.name = 'name search test'
    ontologies3.save

    # test search with acronym
    [
      [ 1, ontologies.first.acronym],
      [ 1, ontologies.last.acronym],
      [ontologies.size, 'TEST-ONT']
    ].each do |count, acronym_search|
      get "/submissions?page=1&pagesize=100&acronym=#{acronym_search}"
      assert last_response.ok?
      submissions = MultiJson.load(last_response.body)
      assert_equal count, submissions['collection'].length
    end

    # test search with name
    [
      [ 1, ontologies.first.name],
      [ 1, ontologies.last.name],
      [ontologies.size - 1, 'TEST-ONT']
    ].each do |count, name_search|
      get "/submissions?page=1&pagesize=100&name=#{name_search}"
      assert last_response.ok?
      submissions = MultiJson.load(last_response.body)
      binding.pry unless submissions['collection'].length.eql?(count)
      assert_equal count, submissions['collection'].length
    end

    # test search with name and acronym
    # search by name
    get '/submissions?page=1&pagesize=100&name=search&acronym=search'
    assert last_response.ok?
    submissions = MultiJson.load(last_response.body)
    assert_equal 1, submissions['collection'].length
    # search by acronym
    get '/submissions?page=1&pagesize=100&name=9&acronym=9'
    assert last_response.ok?
    submissions = MultiJson.load(last_response.body)
    assert_equal 1, submissions['collection'].length
    # search by acronym or name
    get '/submissions?page=1&pagesize=100&name=search&acronym=8'
    assert last_response.ok?
    submissions = MultiJson.load(last_response.body)
    assert_equal 2, submissions['collection'].length

    ontologies.first.name = 'sort by test'
    ontologies.first.save
    sub = ontologies.first.latest_submission(status: :any).bring_remaining
    sub.status = 'retired'
    sub.description = '234'
    sub.creationDate = DateTime.yesterday.to_datetime
    sub.hasOntologyLanguage = LinkedData::Models::OntologyFormat.find('SKOS').first
    sub.save

    #test search with sort
    get '/submissions?page=1&pagesize=100&acronym=tes&name=tes&order_by=ontology_name'
    assert last_response.ok?
    submissions = MultiJson.load(last_response.body)
    refute_empty submissions['collection']
    assert_equal ontologies.map{|x| x.name}.sort, submissions['collection'].map{|x| x['ontology']['name']}

    get '/submissions?page=1&pagesize=100&acronym=tes&name=tes&order_by=creationDate'
    assert last_response.ok?
    submissions = MultiJson.load(last_response.body)
    refute_empty submissions['collection']
    assert_equal ontologies.map{|x| x.latest_submission(status: :any).bring(:creationDate).creationDate}.sort, submissions['collection'].map{|x| DateTime.parse(x['creationDate'])}.reverse

    # test search with format
    get '/submissions?page=1&pagesize=100&acronym=tes&name=tes&hasOntologyLanguage=SKOS'
    assert last_response.ok?
    submissions = MultiJson.load(last_response.body)
    refute_empty submissions['collection']
    assert_equal 1, submissions['collection'].size

    get '/submissions?page=1&pagesize=100&acronym=tes&name=tes&hasOntologyLanguage=OWL'
    assert last_response.ok?
    submissions = MultiJson.load(last_response.body)
    refute_empty submissions['collection']
    assert_equal ontologies.size-1 , submissions['collection'].size

    # test ontology filter with submission filter attributes
    get '/submissions?page=1&pagesize=100&acronym=tes&name=tes&group=group-2&category=category-2&hasOntologyLanguage=OWL'
    assert last_response.ok?
    submissions = MultiJson.load(last_response.body)
    refute_empty submissions['collection']
    assert_equal ontologies2.size + 1 , submissions['collection'].size

    # test ontology filter with status
    get '/submissions?page=1&pagesize=100&status=retired'
    assert last_response.ok?
    submissions = MultiJson.load(last_response.body)
    refute_empty submissions['collection']
    assert_equal 1 , submissions['collection'].size

    get '/submissions?page=1&pagesize=100&status=alpha,beta,production'
    assert last_response.ok?
    submissions = MultiJson.load(last_response.body)
    refute_empty submissions['collection']
    assert_equal ontologies.size - 1 , submissions['collection'].size
    get '/submissions?page=1&pagesize=100&description=234&acronym=234&name=234'
    assert last_response.ok?
    submissions = MultiJson.load(last_response.body)
    assert_equal 1 , submissions['collection'].size
  end

  def test_submissions_param_include
    skip('only for local development regrouping a set of tests')
    test_submissions_default_includes
    test_submissions_all_includes
    test_submissions_custom_includes
  end

  def test_submission_diff
    _, _, onts = create_ontologies_and_submissions(ont_count: 1, submission_count: 2,
                                                   process_submission: true,
                                                   process_options: { process_rdf: true, extract_metadata: false, diff: true} )

    ont = onts.first
    sub = ont.latest_submission(status: :any)

    get "/ontologies/#{ont.acronym}/submissions/#{sub.submissionId}/diff"
  end

  private

  def submission_keys(sub)
    sub.to_hash.keys - %w[@id @type id]
  end

  def assert_submission_contact_structure(sub)
    assert sub["contact"], "Contact should be present"
    return unless sub["contact"].first

    assert_equal(%w[name email id].sort, sub["contact"].first.keys.sort)
  end
end
