require_relative '../test_case'

class TestRepliesController < TestCase

  def before_suite
    ontologies = self.create_ontologies_and_submissions(ont_count: 1, submission_count: 1, process_submission: false)[2]
    @@ontology = ontologies.first

    @@reply_user = "test_reply_user"
    @@user = LinkedData::Models::User.new(
      username: @@reply_user,
      email: "reply_user@example.org",
      password: "reply_user_pass"
    )
    @@user.save

    @@note = LinkedData::Models::Note.new({
      creator: @@user,
      subject: "Test subject note",
      body: "Test body for note",
      relatedOntology: [@@ontology]
    })
    @@note.save

    @@note1 = LinkedData::Models::Note.new({
      creator: @@user,
      subject: "Test subject note 1",
      body: "Test body for note 1",
      relatedOntology: [@@ontology]
    })
    @@note1.save

    @@replies = []
    5.times do |i|
      reply = LinkedData::Models::Notes::Reply.new({
        creator: @@user,
        body: "Test body for reply #{i}"
      })
      reply.save
      @@replies << reply
      @@note.reply = (@@note.reply || []).dup.push(reply)
      @@note.save
      @@note1.reply = (@@note.reply || []).dup.push(reply)
      @@note1.save
    end
  end

  def test_single_reply
    get @@note1.id.to_s
    replies = MultiJson.load(last_response.body)
    reply = replies["reply"].first
    get reply['@id']
    assert last_response.ok?
    retrieved_reply = MultiJson.load(last_response.body)
    assert_equal reply['@id'], retrieved_reply['@id']
  end

  def test_reply_lifecycle
    env("REMOTE_USER", @@user)
    reply = {
      creator: @@user.id.to_s,
      body: "Testing body for reply",
      parent: @@note.id.to_s
    }
    post "/replies", MultiJson.dump(reply), "CONTENT_TYPE" => "application/json"
    assert_equal 201, last_response.status

    new_reply = MultiJson.load(last_response.body)
    get new_reply["@id"]
    assert last_response.ok?

    reply_changes = {body: "New testing body"}
    patch new_reply["@id"], reply_changes.to_json, "CONTENT_TYPE" => "application/json"
    assert last_response.status == 204
    get new_reply["@id"]
    patched_reply = MultiJson.load(last_response.body)
    assert_equal patched_reply["body"], reply_changes[:body]

    delete new_reply["@id"]
    assert last_response.status == 204
  end

end
