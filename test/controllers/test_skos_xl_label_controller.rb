require_relative '../test_case'

class TestSkosXlLabelController < TestCase

  def before_suite
    LinkedData::SampleData::Ontology.create_ontologies_and_submissions({
                                                                         process_submission: true,
                                                                         acronym: 'INRAETHES',
                                                                         name: 'INRAETHES',
                                                                         file_path: './test/data/ontology_files/thesaurusINRAE_nouv_structure.rdf',
                                                                         ont_count: 1,
                                                                         submission_count: 1
                                                                       })
    ont = Ontology.find('INRAETHES-0').include(:acronym).first
    sub = ont.latest_submission
    sub.bring_remaining
    sub.hasOntologyLanguage = LinkedData::Models::OntologyFormat.find('SKOS').first
    sub.save
  end

  def after_suite
    LinkedData::SampleData::Ontology.delete_ontologies_and_submissions
  end

  def test_class_skos_xl_label
    ont = Ontology.find('INRAETHES-0').include(:acronym).first
    class_id = "http://opendata.inrae.fr/thesaurusINRAE/c_16193"
    call = "/ontologies/#{ont.acronym}/classes/#{CGI.escape(class_id)}?display=all&lang=tr"
    get call
    assert last_response.ok?
    concept = MultiJson.load(last_response.body)

    assert_instance_of Array, concept["prefLabelXl"]
    assert_instance_of Array, concept["altLabelXl"]
    assert_instance_of Array, concept["hiddenLabelXl"]

    assert_equal 1, concept["altLabelXl"].size

    label_test(concept["altLabelXl"].first)
  end




  def test_skos_xl_label
    ont = Ontology.find('INRAETHES-0').include(:acronym).first
    label_id = "http://aims.fao.org/aos/agrovoc/xl_tr_1331561625299"
    call = "/ontologies/#{ont.acronym}/skos_xl_labels/#{CGI.escape(label_id)}?lang=tr"
    get call
    assert last_response.ok?

    label = MultiJson.load(last_response.body)
    label_test(label)
  end

  def test_calls_not_found
    ont = Ontology.find('INRAETHES-0').include(:acronym).first
    label_id = "http://aims.fao.org/aos/agrovoc/xl_tr_13315616252_bad"
    get "ontologies/#{ont.acronym}/skos_xl_labels/#{label_id}"
    assert_equal 404, last_response.status
  end

  private
  def label_test(label)
    assert_equal "http://aims.fao.org/aos/agrovoc/xl_tr_1331561625299", label["@id"]
    assert_equal "aktivite", label["literalForm"]
    assert_equal "http://www.w3.org/2008/05/skos-xl#Label", label["@type"]
  end
end
