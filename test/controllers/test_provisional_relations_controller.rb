require_relative '../test_case'

class TestProvisionalRelationsController < TestCase
  def before_suite
    self.delete_ontologies_and_submissions
    @@ontology, classes = self._ontology_and_classes

    @@cls1 = classes[0]
    @@cls2 = classes[1]
    @@cls3 = classes[2]
    @@cls4 = classes[3]
    @@cls5 = classes[4]

    @@test_username = "test_provisional_user"
    @@test_user = LinkedData::Models::User.new(
        username: @@test_username,
        email: "provisional_classes_user@example.org",
        password: "test_user_password"
    )
    @@test_user.save

    # Create a test provisional class
    @@test_pc = LinkedData::Models::ProvisionalClass.new({
        creator: @@test_user,
        label: "Really Nasty Melanoma",
        synonym: ["Test synonym for Prov Class Nasty Melanoma", "Test syn for class Worst Melanoma"],
        definition: ["Test definition for Prov Class Worst and Nasty Melanoma"]
    })
    @@test_pc.save

    #Create a test provisional relation
    @@test_rel = LinkedData::Models::ProvisionalRelation.new({
        creator: @@test_user,
        source: @@test_pc,
        relationType: RDF::IRI.new("http://www.w3.org/2004/02/skos/core#exactMatch"),
        targetClassId: @@cls1.id,
        targetClassOntology: @@ontology
    })
    @@test_rel.save
  end

  def after_suite
    @@test_pc.delete
    @@test_user.delete
  end

  def _ontology_and_classes
    count, acronyms, ontologies = create_ontologies_and_submissions(ont_count: 1, submission_count: 1, process_submission: true)
    ontology = ontologies.first
    sub = ontology.latest_submission(status: :rdf)
    classes = LinkedData::Models::Class.in(sub).include(:prefLabel).page(1, 5).all
    return ontology, classes
  end

  def test_all_provisional_relations
    get '/provisional_relations'
    assert last_response.ok?
    rels = MultiJson.load(last_response.body)
    assert_equal 1, rels.length
  end

  def test_provisional_relation_lifecycle
    rel1 = create_relation(@@cls2, "http://www.w3.org/2004/02/skos/core#closeMatch")
    rel2 = create_relation(@@cls3, "http://www.w3.org/2004/02/skos/core#exactMatch")

    assert_equal "http://www.w3.org/2004/02/skos/core#exactMatch", rel2["relationType"]
    @@test_pc.bring(:relations) if @@test_pc.bring?(:relations)
    assert_equal 3, @@test_pc.relations.length

    delete rel1["@id"]
    assert_equal 204, last_response.status
    delete rel2["@id"]
    assert_equal 204, last_response.status

    test_pc = LinkedData::Models::ProvisionalClass.find(@@test_pc.id).first
    test_pc.bring(:relations)
    assert_equal 1, test_pc.relations.length
  end

  private

  def create_relation(targetCls, relType)
    env("REMOTE_USER", @@test_user)
    rel = {
        creator: @@test_user.id.to_s,
        source: @@test_pc.id.to_s,
        relationType: relType,
        targetClassId: targetCls.id.to_s,
        targetClassOntology: @@ontology.id.to_s
    }
    post "/provisional_relations", MultiJson.dump(rel), "CONTENT_TYPE" => "application/json"
    assert_equal 201, last_response.status

    new_rel = MultiJson.load(last_response.body)
    get new_rel["@id"]
    assert last_response.ok?
    new_rel
  end

end

