require_relative '../test_case'
require 'rexml/document'

class TestDereferenceResourceController < TestCase

  def before_suite
    LinkedData::SampleData::Ontology.create_ontologies_and_submissions({
                                                                         process_submission: true,
                                                                         process_options: { process_rdf: true, extract_metadata: false, generate_missing_labels: false},
                                                                         acronym: 'INRAETHESDEREF',
                                                                         name: 'INRAETHES',
                                                                         file_path: './test/data/ontology_files/thesaurusINRAE_nouv_structure.rdf',
                                                                         ont_count: 1,
                                                                         ontology_format: 'SKOS',
                                                                         submission_count: 1
                                                                       })

    @@graph = "INRAETHESDEREF-0"
    @@uri = CGI.escape("http://opendata.inrae.fr/thesaurusINRAE/c_6496")
  end

  def test_dereference_resource_controller_json
    header 'Accept', 'application/json'
    get "/ontologies/#{@@graph}/resolve/#{@@uri}"
    assert last_response.ok?

    result = last_response.body
    expected_result = <<-JSON
          {
            "@context": {
              "ns0": "http://opendata.inrae.fr/thesaurusINRAE/",
              "rdf": "http://www.w3.org/1999/02/22-rdf-syntax-ns#",
              "owl": "http://www.w3.org/2002/07/owl#",
              "skos": "http://www.w3.org/2004/02/skos/core#"
            },
            "@graph": [
              {
                "@id": "ns0:c_6496",
                "@type": [
                  "owl:NamedIndividual",
                  "skos:Concept"
                ],
                "skos:broader": {
                  "@id": "ns0:c_a9d99f3a"
                },
                "skos:topConceptOf": {
                  "@id": "ns0:mt_65"
                },
                "skos:inScheme": [
                  {
                    "@id": "ns0:thesaurusINRAE"
                  },
                  {
                    "@id": "ns0:mt_65"
                  }
                ],
                "skos:prefLabel": {
                  "@value": "altération de l'ADN",
                  "@language": "fr"
                }
              },
              {
                "@id": "ns0:mt_65",
                "skos:hasTopConcept": {
                  "@id": "ns0:c_6496"
                }
              }
            ]
          }
    JSON
    a = sort_nested_hash(JSON.parse(result))
    b = sort_nested_hash(JSON.parse(expected_result))
    assert_equal b, a
  end

  def test_dereference_resource_controller_xml
    header 'Accept', 'application/xml'
    get "/ontologies/#{@@graph}/resolve/#{@@uri}"
    assert last_response.ok?

    result = last_response.body

    expected_result_1 = <<-XML
          <?xml version="1.0" encoding="UTF-8"?>
          <rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#" xmlns:ns0="http://opendata.inrae.fr/thesaurusINRAE/" xmlns:owl="http://www.w3.org/2002/07/owl#" xmlns:skos="http://www.w3.org/2004/02/skos/core#">
            <owl:NamedIndividual rdf:about="http://opendata.inrae.fr/thesaurusINRAE/c_6496">
              <rdf:type rdf:resource="http://www.w3.org/2004/02/skos/core#Concept"/>
              <skos:broader rdf:resource="http://opendata.inrae.fr/thesaurusINRAE/c_a9d99f3a"/>
              <skos:topConceptOf rdf:resource="http://opendata.inrae.fr/thesaurusINRAE/mt_65"/>
              <skos:inScheme rdf:resource="http://opendata.inrae.fr/thesaurusINRAE/thesaurusINRAE"/>
              <skos:inScheme rdf:resource="http://opendata.inrae.fr/thesaurusINRAE/mt_65"/>
              <skos:prefLabel xml:lang="fr">altération de l'ADN</skos:prefLabel>
            </owl:NamedIndividual>
            <rdf:Description rdf:about="http://opendata.inrae.fr/thesaurusINRAE/mt_65">
              <skos:hasTopConcept rdf:resource="http://opendata.inrae.fr/thesaurusINRAE/c_6496"/>
            </rdf:Description>
          </rdf:RDF>
    XML

    expected_result_2 = <<-XML
        <?xml version="1.0" encoding="UTF-8"?>
        <rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#" xmlns:ns0="http://opendata.inrae.fr/thesaurusINRAE/" xmlns:skos="http://www.w3.org/2004/02/skos/core#" xmlns:owl="http://www.w3.org/2002/07/owl#">
          <skos:Concept rdf:about="http://opendata.inrae.fr/thesaurusINRAE/c_6496">
            <rdf:type rdf:resource="http://www.w3.org/2002/07/owl#NamedIndividual"/>
            <skos:inScheme rdf:resource="http://opendata.inrae.fr/thesaurusINRAE/thesaurusINRAE"/>
            <skos:inScheme rdf:resource="http://opendata.inrae.fr/thesaurusINRAE/mt_65"/>
            <skos:prefLabel xml:lang="fr">altération de l'ADN</skos:prefLabel>
            <skos:topConceptOf rdf:resource="http://opendata.inrae.fr/thesaurusINRAE/mt_65"/>
            <skos:broader rdf:resource="http://opendata.inrae.fr/thesaurusINRAE/c_a9d99f3a"/>
          </skos:Concept>
          <rdf:Description rdf:about="http://opendata.inrae.fr/thesaurusINRAE/mt_65">
            <skos:hasTopConcept rdf:resource="http://opendata.inrae.fr/thesaurusINRAE/c_6496"/>
          </rdf:Description>
        </rdf:RDF>
      XML


    clean_xml = -> (x) { x.strip.gsub('/>', '').gsub('</', '').gsub('<', '').gsub('>', '').split(' ').reject(&:empty?)}


    a = result.gsub('\\"', '"')[1..-2].split("\\n").map{|x| clean_xml.call(x)}.flatten
    b_1 = expected_result_1.split("\n").map{|x| clean_xml.call(x)}.flatten
    b_2 = expected_result_2.split("\n").map{|x| clean_xml.call(x)}.flatten
  
    assert_includes [b_1.sort, b_2.sort], a.sort
  end

  def test_dereference_resource_controller_ntriples
    header 'Accept', 'application/n-triples'
    get "/ontologies/#{@@graph}/resolve/#{@@uri}"
    assert last_response.ok?

    result = last_response.body
    expected_result = <<-NTRIPLES
          <http://opendata.inrae.fr/thesaurusINRAE/c_6496> <http://www.w3.org/1999/02/22-rdf-syntax-ns#type> <http://www.w3.org/2002/07/owl#NamedIndividual> .
          <http://opendata.inrae.fr/thesaurusINRAE/c_6496> <http://www.w3.org/1999/02/22-rdf-syntax-ns#type> <http://www.w3.org/2004/02/skos/core#Concept> .
          <http://opendata.inrae.fr/thesaurusINRAE/c_6496> <http://www.w3.org/2004/02/skos/core#broader> <http://opendata.inrae.fr/thesaurusINRAE/c_a9d99f3a> .
          <http://opendata.inrae.fr/thesaurusINRAE/c_6496> <http://www.w3.org/2004/02/skos/core#topConceptOf> <http://opendata.inrae.fr/thesaurusINRAE/mt_65> .
          <http://opendata.inrae.fr/thesaurusINRAE/c_6496> <http://www.w3.org/2004/02/skos/core#inScheme> <http://opendata.inrae.fr/thesaurusINRAE/thesaurusINRAE> .
          <http://opendata.inrae.fr/thesaurusINRAE/c_6496> <http://www.w3.org/2004/02/skos/core#inScheme> <http://opendata.inrae.fr/thesaurusINRAE/mt_65> .
          <http://opendata.inrae.fr/thesaurusINRAE/c_6496> <http://www.w3.org/2004/02/skos/core#prefLabel> "alt\\u00E9rationdel'ADN"@fr .
          <http://opendata.inrae.fr/thesaurusINRAE/mt_65> <http://www.w3.org/2004/02/skos/core#hasTopConcept> <http://opendata.inrae.fr/thesaurusINRAE/c_6496> .
    NTRIPLES
    a = result.gsub(' ', '').split("\n").reject(&:empty?)
    b = expected_result.gsub(' ', '').split("\n").reject(&:empty?)
    assert_equal b.sort, a.sort
  end

  def test_dereference_resource_controller_turtle
    header 'Accept', 'text/turtle'
    get "/ontologies/#{@@graph}/resolve/#{@@uri}"
    assert last_response.ok?

    result = last_response.body
    expected_result = <<-TURTLE
          @prefix rdf: <http://www.w3.org/1999/02/22-rdf-syntax-ns#> .
          @prefix ns0: <http://opendata.inrae.fr/thesaurusINRAE/> .
          @prefix owl: <http://www.w3.org/2002/07/owl#> .
          @prefix skos: <http://www.w3.org/2004/02/skos/core#> .
          
          ns0:c_6496
              a owl:NamedIndividual, skos:Concept ;
              skos:broader ns0:c_a9d99f3a ;
              skos:inScheme ns0:mt_65, ns0:thesaurusINRAE ;
              skos:prefLabel "altération de l'ADN"@fr ;
              skos:topConceptOf ns0:mt_65 .
          
          ns0:mt_65
              skos:hasTopConcept ns0:c_6496 .
    TURTLE
    a = result.gsub(' ', '').split("\n").reject(&:empty?)
    b = expected_result.gsub(' ', '').split("\n").reject(&:empty?)

    assert_equal b.sort, a.sort
  end

  private

  def sort_nested_hash(hash)
    sorted_hash = {}

    hash.each do |key, value|
      if value.is_a?(Hash)
        sorted_hash[key] = sort_nested_hash(value)
      elsif value.is_a?(Array)
        sorted_hash[key] = value.map { |item| item.is_a?(Hash) ? sort_nested_hash(item) : item }.sort_by { |item| item.to_s }
      else
        sorted_hash[key] = value
      end
    end

    sorted_hash.sort.to_h
  end

end
