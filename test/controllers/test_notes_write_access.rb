require_relative '../test_case'

# Notes and replies have no controller-level write check. Ownership is enforced
# in ontologies_linked_data: LinkedData::Models::Base#save/#delete call
# write_permission_check, which allows the object's `creator` or an admin.
# These tests pin that behaviour at the HTTP level.
class TestNotesWriteAccess < TestCase

  def before_suite
    ontologies = create_ontologies_and_submissions(ont_count: 1, submission_count: 1, process_submission: false)[2]
    @@ontology = ontologies.first
    @@owner = self.class.ensure_user('test_note_owner')
    @@other = self.class.ensure_user('test_note_other')
    @@admin = self.class.ensure_user('test_note_admin')
    self.class.make_admin(@@admin)
  end

  def after_suite
    %w[test_note_owner test_note_other test_note_admin].each { |u| self.class.delete_user(u) }
    delete_ontologies_and_submissions
  end

  def test_non_owner_cannot_patch_note
    note = create_note(@@owner)
    with_settings(enable_security: true) do
      patch "#{note_path(note)}?apikey=#{@@other.apikey}", MultiJson.dump(body: 'hijacked'), 'CONTENT_TYPE' => 'application/json'
      assert_equal 403, last_response.status
    end
    assert_equal 'original body', reload_note(note).body
  end

  def test_non_owner_cannot_delete_note
    note = create_note(@@owner)
    with_settings(enable_security: true) do
      delete "#{note_path(note)}?apikey=#{@@other.apikey}"
      assert_equal 403, last_response.status
    end
    refute_nil reload_note(note)
  end

  def test_non_owner_cannot_delete_note_with_replies
    note = create_note(@@owner)
    add_reply(note, @@owner)
    with_settings(enable_security: true) do
      delete "#{note_path(note)}?apikey=#{@@other.apikey}"
      assert_equal 403, last_response.status
    end
    note = reload_note(note)
    refute_nil note
    note.bring(:reply)
    assert_equal 1, note.reply.length
  end

  def test_owner_can_patch_and_delete_note
    note = create_note(@@owner)
    with_settings(enable_security: true) do
      patch "#{note_path(note)}?apikey=#{@@owner.apikey}", MultiJson.dump(body: 'edited'), 'CONTENT_TYPE' => 'application/json'
      assert_equal 204, last_response.status
      assert_equal 'edited', reload_note(note).body

      delete "#{note_path(note)}?apikey=#{@@owner.apikey}"
      assert_equal 204, last_response.status
    end
    assert_nil reload_note(note)
  end

  def test_admin_can_patch_and_delete_note
    note = create_note(@@owner)
    with_settings(enable_security: true) do
      patch "#{note_path(note)}?apikey=#{@@admin.apikey}", MultiJson.dump(body: 'moderated'), 'CONTENT_TYPE' => 'application/json'
      assert_equal 204, last_response.status
      assert_equal 'moderated', reload_note(note).body

      delete "#{note_path(note)}?apikey=#{@@admin.apikey}"
      assert_equal 204, last_response.status
    end
    assert_nil reload_note(note)
  end

  def test_non_owner_cannot_patch_or_delete_reply
    reply = add_reply(create_note(@@owner), @@owner)
    with_settings(enable_security: true) do
      patch "#{reply_path(reply)}?apikey=#{@@other.apikey}", MultiJson.dump(body: 'hijacked'), 'CONTENT_TYPE' => 'application/json'
      assert_equal 403, last_response.status

      delete "#{reply_path(reply)}?apikey=#{@@other.apikey}"
      assert_equal 403, last_response.status
    end
    reply = reload_reply(reply)
    refute_nil reply
    assert_equal 'reply body', reply.body
  end

  def test_owner_and_admin_can_patch_and_delete_reply
    note = create_note(@@owner)
    own = add_reply(note, @@owner)
    moderated = add_reply(note, @@owner)
    with_settings(enable_security: true) do
      patch "#{reply_path(own)}?apikey=#{@@owner.apikey}", MultiJson.dump(body: 'edited'), 'CONTENT_TYPE' => 'application/json'
      assert_equal 204, last_response.status
      delete "#{reply_path(own)}?apikey=#{@@owner.apikey}"
      assert_equal 204, last_response.status

      patch "#{reply_path(moderated)}?apikey=#{@@admin.apikey}", MultiJson.dump(body: 'moderated'), 'CONTENT_TYPE' => 'application/json'
      assert_equal 204, last_response.status
      delete "#{reply_path(moderated)}?apikey=#{@@admin.apikey}"
      assert_equal 204, last_response.status
    end
    assert_nil reload_reply(own)
    assert_nil reload_reply(moderated)
  end

  private

  def create_note(creator)
    LinkedData::Models::Note.new(
      creator: creator,
      subject: 'write access subject',
      body: 'original body',
      relatedOntology: [@@ontology]
    ).save
  end

  def add_reply(note, creator)
    reply = LinkedData::Models::Notes::Reply.new(creator: creator, body: 'reply body').save
    note.bring(:reply)
    note.reply = note.reply.dup.push(reply)
    note.save(override_security: true)
    reply
  end

  def note_path(note)
    "/notes/#{note.id.to_s.split('/').last}"
  end

  def reply_path(reply)
    "/replies/#{reply.id.to_s.split('/').last}"
  end

  def reload_note(note)
    LinkedData::Models::Note.find(note.id).include(:body).first
  end

  def reload_reply(reply)
    LinkedData::Models::Notes::Reply.find(reply.id).include(:body).first
  end
end
