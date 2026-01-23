require 'multi_json'
require 'cgi'

class PropertiesSearchController < ApplicationController
  namespace "/property_search" do
    # execute a search query
    get do
      process_search()
    end

    post do
      process_search()
    end

    private

    def process_search(params=nil)
      params ||= @params
      text = params["q"]

      query = get_properties_search_query(text, params)
      # puts "Properties query: #{query}, params: #{params}"
      set_page_params(params)
      docs = Array.new
      resp = LinkedData::Models::OntologyProperty.search(query, params)
      total_found = resp["response"]["numFound"]
      add_matched_fields(resp, Sinatra::Helpers::SearchHelper::MATCH_TYPE_LABEL)
      ontology_rank = LinkedData::Models::Ontology.rank

      resp["response"]["docs"].each do |doc|
        doc = doc.symbolize_keys
        doc[:matchType] = resp["match_types"][doc[:id]]
        resource_id = doc[:resource_id]
        doc.delete :resource_id
        doc[:id] = resource_id

        ontology_uri = doc[:ontologyId].sub(/\/submissions\/.*/, "")
        ontology = LinkedData::Models::Ontology.read_only(id: ontology_uri, acronym: doc[:submissionAcronym])
        submission = LinkedData::Models::OntologySubmission.read_only(id: doc[:ontologyId], ontology: ontology)
        doc[:submission] = submission
        doc[:ontology_rank] = (ontology_rank[doc[:submissionAcronym]] && !ontology_rank[doc[:submissionAcronym]].empty?) ? ontology_rank[doc[:submissionAcronym]][:normalizedScore] : 0.0
        instance = property_object_instance(doc[:propertyType]).read_only(doc)
        docs.push(instance)
      end

      docs.sort! {|a, b| [b[:score], b[:ontology_rank]] <=> [a[:score], a[:ontology_rank]]}

      # #need to return a Page object
      page = page_object(docs, total_found)

      reply 200, page
    end

  end
end
