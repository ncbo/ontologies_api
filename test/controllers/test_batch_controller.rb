require_relative '../test_case'

class TestBatchController < TestCase
  def before_suite
    LinkedData::SampleData::Ontology.delete_ontologies_and_submissions
    @@ontologies = LinkedData::SampleData::Ontology.sample_owl_ontologies(process_submission: true)
  end

  def test_class_batch_one_ontology
    bro = @@ontologies.map { |x| x.id.to_s }.select { |y| y.include? "BRO"}.first
    assert bro, "BRO is not found to execute batch test."
    class_ids = {
      "http://bioontology.org/ontologies/BiomedicalResourceOntology.owl#Information_Resource" => "Information Resource",
      "http://bioontology.org/ontologies/BiomedicalResourceOntology.owl#Data_Resource" => "Data Resource",
      "http://bioontology.org/ontologies/BiomedicalResourceOntology.owl#Clinical_Care_Data" => "Clinical Care Data",
      "http://bioontology.org/ontologies/BiomedicalResourceOntology.owl#Aggregate_Human_Data" => "Aggregate Human Data"
    }
    collection = class_ids.keys.map { |x| { "class" => x , "ontology" => bro } }
    call_params = {
      "http://www.w3.org/2002/07/owl#Class" => {
        "collection" => collection,
        "display" => "prefLabel,synonym"
      }
    }
    post "/batch/", call_params
    assert last_response.ok?
    data = MultiJson.load(last_response.body)
    classes = data["http://www.w3.org/2002/07/owl#Class"]
    assert_equal 4, classes.length
    classes.each do |klass|
      assert_instance_of String, klass["prefLabel"]
      assert_instance_of Array, klass["synonym"]
      assert klass["prefLabel"] == class_ids[klass["@id"]]
    end
  end

  def test_class_wrong_params
    bro = @@ontologies.map { |x| x.id.to_s }.select { |y| y.include? "BRO"}.first
    assert bro, "BRO is not found to execute batch test."
    class_ids = {
      "http://bioontology.org/ontologies/BiomedicalResourceOntology.owl#Information_Resource" => "Information Resource",
      "http://bioontology.org/ontologies/BiomedicalResourceOntology.owl#Data_Resource" => "Data Resource"
    }
    collection = class_ids.keys
    call_params = {
      "http://www.w3.org/2002/07/owl#Class" => {
        "collection" => collection,
        "display" => "prefLabel,synonym"
      }
    }
    post "/batch/", call_params
    assert_equal 422, last_response.status
  end

  def test_class_batch_multiple
    bro = @@ontologies.map { |x| x.id.to_s }.select { |y| y.include? "BRO"}.first
    mccl = @@ontologies.map { |x| x.id.to_s }.select { |y| y.include? "MCCL"}.first
    assert bro, "BRO is not found to execute batch test."
    assert mccl, "mccl is not found to execute batch test."
    class_ids = {
      "http://bioontology.org/ontologies/BiomedicalResourceOntology.owl#Information_Resource" => "Information Resource",
      "http://bioontology.org/ontologies/BiomedicalResourceOntology.owl#Data_Resource" => "Data Resource",
      "http://bioontology.org/ontologies/BiomedicalResourceOntology.owl#Clinical_Care_Data" => "Clinical Care Data",
      "http://bioontology.org/ontologies/BiomedicalResourceOntology.owl#Aggregate_Human_Data" => "Aggregate Human Data",
      "http://purl.obolibrary.org/obo/MCBCC_0000288#ChromosomalMutation" => "chromosomal mutation",
      "http://purl.obolibrary.org/obo/MCBCC_0000275#ReceptorAntagonists" => "receptor antagonists"
    }
    collection = class_ids.keys.map { |x| { "class" => x , "ontology" => (x.include?("obolibrary") ? mccl : bro) } }
    call_params = {
      "http://www.w3.org/2002/07/owl#Class" => {
        "collection" => collection,
        "display" => "prefLabel"
      }
    }
    post "/batch/", call_params
    assert last_response.ok?
    data = MultiJson.load(last_response.body)
    classes = data["http://www.w3.org/2002/07/owl#Class"]
    assert_equal 6, classes.length
    classes.each do |klass|
      assert_instance_of String, klass["prefLabel"]
      refute klass["synonym"]
      assert_equal klass["prefLabel"], class_ids[klass["@id"]]
    end
  end


  def test_class_all_bro
    mccl = @@ontologies.select { |y| y.id.to_s.include? "MCCL"}.first
    assert mccl, "mccl is not found to execute batch test."
    # binding.pry
    classes = LinkedData::Models::Class.in(mccl.latest_submission).include(:prefLabel).page(1,500).read_only.all
    class_ids = {}
    classes.each do |klass|
      class_ids[klass.id.to_s]=klass.prefLabel
    end
    collection = class_ids.keys.map { |x| { "class" => x , "ontology" => mccl.id.to_s } }
    call_params = {
      "http://www.w3.org/2002/07/owl#Class" => {
        "collection" => collection,
        "display" => "prefLabel"
      }
    }
    post "/batch/", call_params
    assert last_response.ok?
#    refute last_response.ok?
    data = MultiJson.load(last_response.body)
    classes_response = data["http://www.w3.org/2002/07/owl#Class"]
    assert_equal classes.length, classes_response.length
    classes_response.each do |klass|
      assert_instance_of String, klass["prefLabel"]
      assert_equal klass["prefLabel"], class_ids[klass["@id"]]
    end
  end
end
