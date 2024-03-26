require_relative '../test_case_helpers'

class TestHTTPCacheHelper < TestCaseHelpers

  def before_suite
    raise Exception, "Redis is unavailable, caching will not function" if LinkedData::HTTPCache.redis.ping.nil?
    self.delete_ontologies_and_submissions
    ontologies = self._ontologies
    @@ontology = ontologies.shift
    @@ontology_alt = ontologies.shift
    @@ontology.bring_remaining
    @@ontology_alt.bring_remaining

    @@note_user = "test_note_user"
    @@user = LinkedData::Models::User.new(
      username: @@note_user,
      email: "note_user@example.org",
      password: "note_user_pass"
    )
    @@user.save

    @@note = LinkedData::Models::Note.new({
      creator: @@user,
      subject: "Test subject",
      body: "Test body for note",
      relatedOntology: [@@ontology]
    })
    @@note.save

    @@note_alt = LinkedData::Models::Note.new({
      creator: @@user,
      subject: "Test subject alt",
      body: "Test body for note alt",
      relatedOntology: [@@ontology_alt]
    })
    @@note_alt.save

    @orig_enable_cache = LinkedData.settings.enable_http_cache
    LinkedData.settings.enable_http_cache = true
  end

  def after_suite
    LinkedData.settings.enable_http_cache = @orig_enable_cache
    LinkedData::HTTPCache.invalidate_all
  end

  def _ontologies
    results = create_ontologies_and_submissions(ont_count: 2, submission_count: 1, process_submission: false)
    return results[2]
  end

  def test_cached_collection
    #puts LinkedData.settings.enable_http_cache
    get '/ontologies'
    assert_equal 200, last_response.status
    token = last_response.headers["Last-Modified"]
    get '/ontologies', {}, {"HTTP_IF_MODIFIED_SINCE" => token}
    assert_equal 304, last_response.status
    sleep(1)
    @@ontology.name = "Test new name"
    @@ontology.save
    get '/ontologies'
    assert_equal 200, last_response.status
  end

  def test_cached_single
    #puts LinkedData.settings.enable_http_cache
    get '/ontologies/' + @@ontology.acronym
    assert_equal 200, last_response.status
    token = last_response.headers["Last-Modified"]
    get '/ontologies/' + @@ontology.acronym, {}, {"HTTP_IF_MODIFIED_SINCE" => token}
    assert_equal 304, last_response.status
    sleep(1)
    @@ontology.name = "Test new name"
    @@ontology.save
    get '/ontologies/' + @@ontology.acronym
    assert_equal 200, last_response.status
  end

  def test_cached_segment
    #puts LinkedData.settings.enable_http_cache
    get "/ontologies/#{@@ontology.acronym}/notes"
    token = last_response.headers["Last-Modified"]
    assert_equal 200, last_response.status
    get "/ontologies/#{@@ontology.acronym}/notes", {}, {"HTTP_IF_MODIFIED_SINCE" => token}
    assert_equal 304, last_response.status
    get "/ontologies/#{@@ontology_alt.acronym}/notes"
    token_alt = last_response.headers["Last-Modified"]
    assert_equal 200, last_response.status
    get "/ontologies/#{@@ontology_alt.acronym}/notes", {}, {"HTTP_IF_MODIFIED_SINCE" => token_alt}
    assert_equal 304, last_response.status
    sleep(1)
    @@note.subject = "New subject"
    @@note.save
    get "/ontologies/#{@@ontology.acronym}/notes", {}, {"HTTP_IF_MODIFIED_SINCE" => token}
    assert_equal 200, last_response.status
    get "/ontologies/#{@@ontology_alt.acronym}/notes", {}, {"HTTP_IF_MODIFIED_SINCE" => token_alt}
    assert_equal 304, last_response.status
  end
end
