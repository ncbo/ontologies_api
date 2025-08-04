require 'cgi'
require_relative '../test_case'

class TestNotesController < TestCase

  def before_suite
    self.delete_ontologies_and_submissions
    @@ontology, @@cls = self._ontology_and_class

    @@note_user = "test_note_user"
    @@user = LinkedData::Models::User.new(
      username: @@note_user,
      email: "note_user@example.org",
      password: "note_user_pass"
    )
    @@user.save

    @@notes = []
    5.times do |i|
      note = LinkedData::Models::Note.new({
        creator: @@user,
        subject: "Test subject #{i}",
        body: "Test body for note #{i}",
        relatedOntology: [@@ontology],
        relatedClass: [@@cls]
      })
      note.save
      @@notes << note
    end
  end

  def _ontology_and_class
    count, acronyms, ontologies = create_ontologies_and_submissions(ont_count: 1, submission_count: 1, process_submission: true)
    ontology = ontologies.first
    sub = ontology.latest_submission(status: :rdf)
    cls = LinkedData::Models::Class.in(sub).include(:prefLabel, :notes).page(1, 1).first
    return ontology, cls
  end

  def test_all_notes
    get '/notes'
    assert last_response.ok?
    notes = MultiJson.load(last_response.body)
    assert_operator 5, :<=, notes.length
  end

  def test_single_note
    get '/notes'
    notes = MultiJson.load(last_response.body)
    note = notes.first
    get note['@id']
    assert last_response.ok?
    retrieved_note = MultiJson.load(last_response.body)
    assert_equal note["@id"], retrieved_note["@id"]
  end

  def test_note_lifecycle
    env("REMOTE_USER", @@user)
    note = {
      creator: @@user.id.to_s,
      body: "Testing body",
      subject: "Testing subject",
      relatedOntology: [@@ontology.id.to_s]
    }
    post "/notes", MultiJson.dump(note), "CONTENT_TYPE" => "application/json"
    assert_equal 201, last_response.status

    new_note = MultiJson.load(last_response.body)
    get new_note["@id"]
    assert last_response.ok?
    assert_equal 200, last_response.status

    note_changes = {body: "New testing body"}
    patch new_note["@id"], MultiJson.dump(note_changes), "CONTENT_TYPE" => "application/json"
    assert_equal 204, last_response.status
    get new_note["@id"]
    patched_note = MultiJson.load(last_response.body)
    assert_equal patched_note["body"], note_changes[:body]

    delete new_note["@id"]
    assert_equal 204, last_response.status
  end

  def test_proposal_lifecycle
    env("REMOTE_USER", @@user)
    note = {
      :subject=>"New Term Proposal: Sleep Study Facility",
      :creator=>@@user.id.to_s,
      :created=>"Tue, 15 Jun 2010 07:54:15 -0700",
      :relatedOntology=>[@@ontology.id.to_s],
      :proposal=>
        {
          :type=>"ProposalNewClass",
          :contactInfo=>"",
          :reasonForChange=>"Physiology facility child",
          :label=>"Sleep Study Facility",
          :definition=>["A facility or core devoted to sleep studies"],
          :parent=>nil
        }
     }

     post "/notes", MultiJson.dump(note), "CONTENT_TYPE" => "application/json"
     assert_equal 201, last_response.status

     new_note = MultiJson.load(last_response.body)
     # assert_equal 'blah', new_note
     get new_note["@id"]
     assert last_response.ok?

     note_changes = {proposal: {label: "New sleed study facility"}}
     patch new_note["@id"], MultiJson.dump(note_changes), "CONTENT_TYPE" => "application/json"
     assert_equal 204, last_response.status
     get new_note["@id"]
     patched_note = MultiJson.load(last_response.body)
     refute_nil patched_note['proposal']['label']
     assert_equal patched_note['proposal']['label'], note_changes[:proposal][:label]

     delete new_note["@id"]
     assert_equal 204, last_response.status
  end

  def test_notes_for_ontology
    get @@ontology.id.to_s
    ont = MultiJson.load(last_response.body)
    get ont["links"]["notes"]
    notes = MultiJson.load(last_response.body)
    test_note = notes.select {|n| n["subject"].eql?("Test subject 1")}
    assert_equal 1, test_note.length
    assert_operator 5, :<=, notes.length
  end

  def test_notes_for_class
    get "/ontologies/#{@@ontology.acronym}/classes/#{CGI.escape(@@cls.id.to_s)}"
    cls = MultiJson.load(last_response.body)
    get cls["links"]["notes"]
    notes = MultiJson.load(last_response.body)
    test_note = notes.select {|n| n["subject"].eql?("Test subject 1")}
    assert_equal 1, test_note.length
    assert_operator 5, :<=, notes.length
  end

  def test_note_creator_ignores_user_input
    # Set current user for this test
    env("REMOTE_USER", @@user)
    post "/notes", MultiJson.dump({
      body: "Testing body",
      subject: "Testing subject", 
      relatedOntology: [@@ontology.id.to_s],
      creator: "wrong_user_id"
    }), { "CONTENT_TYPE" => "application/json" }

    assert_equal 201, last_response.status

    new_note = MultiJson.load(last_response.body)
    get new_note["@id"]
    assert last_response.ok?

    # Verify the creator is the current user, not the wrong user
    retrieved_note = MultiJson.load(last_response.body)
    assert_equal @@user.id.to_s, retrieved_note["creator"]
    refute_equal "wrong_user_id", retrieved_note["creator"]
  end

end
