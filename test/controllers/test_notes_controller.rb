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
    assert notes.length >= 5
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
    note = {
      creator: @@user.id.to_s,
      body: "Testing body",
      subject: "Testing subject",
      relatedOntology: [@@ontology.id.to_s]
    }
    post "/notes", MultiJson.dump(note), "CONTENT_TYPE" => "application/json"
    assert last_response.status == 201

    new_note = MultiJson.load(last_response.body)
    get new_note["@id"]
    assert last_response.ok?

    note_changes = {body: "New testing body"}
    patch new_note["@id"], MultiJson.dump(note_changes), "CONTENT_TYPE" => "application/json"
    assert last_response.status == 204
    get new_note["@id"]
    patched_note = MultiJson.load(last_response.body)
    assert_equal patched_note["body"], note_changes[:body]

    delete new_note["@id"]
    assert last_response.status == 204
  end

  def test_proposal_lifecycle
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
     assert last_response.status == 201

     new_note = MultiJson.load(last_response.body)
     get new_note["@id"]
     assert last_response.ok?

     note_changes = {proposal: {label: "New sleed study facility"}}
     patch new_note["@id"], MultiJson.dump(note_changes), "CONTENT_TYPE" => "application/json"
     assert last_response.status == 204
     get new_note["@id"]
     patched_note = MultiJson.load(last_response.body)
     assert_equal patched_note["label"], note_changes[:label]

     delete new_note["@id"]
     assert last_response.status == 204
  end

  def test_notes_for_ontology
    get @@ontology.id.to_s
    ont = MultiJson.load(last_response.body)
    get ont["links"]["notes"]
    notes = MultiJson.load(last_response.body)
    test_note = notes.select {|n| n["subject"].eql?("Test subject 1")}
    assert test_note.length == 1
    assert notes.length >= 5
  end

  def test_notes_for_class
    get "/ontologies/#{@@ontology.acronym}/classes/#{CGI.escape(@@cls.id.to_s)}"
    cls = MultiJson.load(last_response.body)
    get cls["links"]["notes"]
    notes = MultiJson.load(last_response.body)
    test_note = notes.select {|n| n["subject"].eql?("Test subject 1")}
    assert test_note.length == 1
    assert notes.length >= 5
  end
end
