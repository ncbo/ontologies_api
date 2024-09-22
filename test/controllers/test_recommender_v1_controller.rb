require_relative '../test_case'

class TestRecommenderV1Controller < TestCase

  def self.before_suite
    LinkedData::SampleData::Ontology.delete_ontologies_and_submissions
    @@ontologies = LinkedData::SampleData::Ontology.sample_owl_ontologies(process_submission: true)
    @@text = <<eos
Ginsenosides chemistry, biosynthesis, analysis, and potential health effects in software concept or data." "Ginsenosides are a special group of triterpenoid saponins that can be classified into two groups by the skeleton of their aglycones, namely dammarane- and oleanane-type. Ginsenosides are found nearly exclusively in Panax species (ginseng) and up to now more than 150 naturally occurring ginsenosides have been isolated from roots, leaves/stems, fruits, and/or flower heads of ginseng. The same concept indicates Ginsenosides have been the target of a lot of research as they are believed to be the main active principles behind the claims of ginsengs efficacy. The potential health effects of ginsenosides that are discussed in this chapter include anticarcinogenic, immunomodulatory, anti-inflammatory, antiallergic, antiatherosclerotic, antihypertensive, and antidiabetic effects as well as antistress activity and effects on the central nervous system. Ginsensoides can be metabolized in the stomach (acid hydrolysis) and in the gastrointestinal tract (bacterial hydrolysis) or transformed to other ginsenosides by drying and steaming of ginseng to more bioavailable and bioactive ginsenosides. The metabolization and transformation of intact ginsenosides, which seems to play an important role for their potential health effects, are discussed. Qualitative and quantitative analytical techniques for the analysis of ginsenosides are important in relation to quality control of ginseng products and plant material and for the determination of the effects of processing of plant material as well as for the determination of the metabolism and bioavailability of ginsenosides. Analytical techniques for the analysis of ginsenosides that are described in this chapter are thin-layer chromatography (TLC), high-performance liquid chromatography (HPLC) combined with various detectors, gas chromatography (GC), colorimetry, enzyme immunoassays (EIA), capillary electrophoresis (CE), nuclear magnetic resonance (NMR) spectroscopy, and spectrophotometric methods.
eos
  end

  def test_recommend_query_failure
    params = {}
    get "/recommender_v1", params
    assert last_response.status == 400
  end

  def test_recommend_query
    params = {
       :text => @@text
    }
    get "/recommender_v1", params
    assert last_response.ok?
    recommendations = MultiJson.load(last_response.body)
    assert_instance_of(Array, recommendations)
    assert_equal(3, recommendations.length, msg='Failed to return 3 recommendations')
    rec = recommendations.first
    assert_instance_of(Hash, rec)
    ont_acronyms = @@ontologies.map {|o| o.bring(:acronym); o.acronym }
    assert ont_acronyms.include? rec['ontology']['acronym']
    assert rec['annotatedClasses'].length == 0  # no classes requested
    assert rec['numTermsMatched'] > 0
    assert rec['numTermsTotal'] > 0
    assert rec['numTermsTotal'] >= rec['numTermsMatched']
    assert recommendations[0]['score'].to_i >= recommendations[1]['score'].to_i
    assert recommendations[1]['score'].to_i >= recommendations[2]['score'].to_i
  end

end
