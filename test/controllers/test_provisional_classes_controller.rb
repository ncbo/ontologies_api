require_relative '../test_case'

class TestProvisionalClassesController < TestCase
  def before_suite
    self.delete_ontologies_and_submissions
    @@ontology, classes = self._ontology_and_classes

    @@cls = classes[0]
    @@cls1 = classes[1]

    @@test_username = "test_provisional_user"
    @@test_user = LinkedData::Models::User.new(
        username: @@test_username,
        email: "provisional_classes_user@example.org",
        password: "test_user_password"
    )
    @@test_user.save

    # second user for testing stripping of system_controlled parameter
    @@other_username = "other_provisional_user"
    @@other_user = LinkedData::Models::User.new(
        username: @@other_username,
        email: "other_provisional_classes_user@example.org",
        password: "test_user_password"
      )
    @@other_user.save

    # Create a test provisional class
    @@test_pc = {label: "Really Nasty Melanoma", synonym: ["Nasty Melanoma", "Worst Melanoma"], definition: ["Melanoma of the nastiest kind known to men"], creator: @@test_user.id.to_s}

    @@pcs = []
    3.times do |i|
      pc = ProvisionalClass.new({
          creator: @@test_user,
          label: "Test Prov Class #{i}",
          synonym: ["Test synonym for Prov Class #{i}"],
          definition: ["Test definition for Prov Class #{i}"]
      })
      pc.save
      @@pcs << pc
    end
  end

  def after_suite
    3.times do |i|
      @@pcs[i].delete
    end
    @@test_user.delete
  end

  def _ontology_and_classes
    count, acronyms, ontologies = create_ontologies_and_submissions(ont_count: 1, submission_count: 1, process_submission: true)
    ontology = ontologies.first
    sub = ontology.latest_submission(status: :rdf)
    classes = LinkedData::Models::Class.in(sub).include(:prefLabel).page(1, 2).all
    return ontology, classes
  end

  def test_all_provisional_classes
    get '/provisional_classes'
    assert last_response.ok?
    pcs = MultiJson.load(last_response.body)
    assert pcs.length >= 3
  end

  def test_single_provisional_class
    get '/provisional_classes'
    pcs = MultiJson.load(last_response.body)
    pc = pcs["collection"].first
    get pc['@id']
    assert last_response.ok?
    retrieved_pc = MultiJson.load(last_response.body)
    assert_equal pc["@id"], retrieved_pc["@id"]
  end

  def test_user_provisional_classes
    get "/users/#{@@test_username}/provisional_classes"
    assert_equal 200, last_response.status
    pcs = MultiJson.load(last_response.body)
    assert_equal 3, pcs.length
  end

  def test_provisional_class_lifecycle
    env("REMOTE_USER", @@test_user)
    pc = {
        creator: @@test_user.id.to_s,
        label: "A Newest Form of Cancer",
        synonym: ["New Cancer", "2013 Cancer"],
        definition: ["A new form of cancer has just been discovered."]
    }
    post "/provisional_classes", MultiJson.dump(pc), "CONTENT_TYPE" => "application/json"
    assert_equal 201, last_response.status

    new_pc = MultiJson.load(last_response.body)
    get new_pc["@id"]
    assert last_response.ok?

    pc_changes = {label: "A Form of Cancer No Longer New", permanentId: "http://purl.obolibrary.org/obo/MI_0914"}
    patch new_pc["@id"], MultiJson.dump(pc_changes), "CONTENT_TYPE" => "application/json"

    assert_equal 204, last_response.status
    get new_pc["@id"]
    patched_pc = MultiJson.load(last_response.body)
    assert_equal patched_pc["label"], pc_changes[:label]

    #test patch with relations
    pc_changes = {
        label: "A Form of Cancer change with Relations",
        permanentId: "http://purl.obolibrary.org/obo/MI_0925",
        relations: [
          {
              creator: @@other_user.id.to_s,
              relationType: "http://www.w3.org/2004/02/skos/core#exactMatch",
              targetClassId: @@cls.id.to_s,
              targetClassOntology: @@ontology.id.to_s
          }
        ]
    }
    patch new_pc["@id"], MultiJson.dump(pc_changes), "CONTENT_TYPE" => "application/json"

    assert_equal 204, last_response.status
    get new_pc["@id"]
    patched_pc = MultiJson.load(last_response.body)
    assert_equal patched_pc["label"], pc_changes[:label]
    assert_equal 1, patched_pc["relations"].length unless patched_pc["relations"].empty?
    # test striping of system_controlled parameter
    refute_match 'other_provisional_user', patched_pc["creator"]

    #test patch with a different relation
    pc_changes = {
        label: "A Form of Cancer change with a different Relation",
        permanentId: "http://purl.obolibrary.org/obo/MI_0925",
        relations: [
            {
                creator: @@test_user.id.to_s,
                relationType: "http://www.w3.org/2004/02/skos/core#exactMatch",
                targetClassId: @@cls1.id.to_s,
                targetClassOntology: @@ontology.id.to_s
            }
        ]
    }
    patch new_pc["@id"], MultiJson.dump(pc_changes), "CONTENT_TYPE" => "application/json"
    get new_pc["@id"]
    patched_pc = MultiJson.load(last_response.body)

    unless patched_pc["relations"].empty?
      assert_equal 1, patched_pc["relations"].length
      assert_equal @@cls1.id.to_s, patched_pc["relations"][0]["targetClassId"]
    end

    delete new_pc["@id"]
    assert_equal 204, last_response.status
  end
end
