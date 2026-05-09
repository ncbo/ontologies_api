require 'multi_json'
require 'cgi'

class SearchController < ApplicationController
  namespace "/search" do
    # execute a search query

    get do
      page = process_search
      reply 200, page
    end

    post do
      page = process_search
      reply 200, page
    end

    namespace "/ontologies" do
      get do
        query = params[:query] || params[:q]
        options = get_ontology_metadata_search_options(params)
        page_data = search(Ontology, query, options)
        total_found = page_data.aggregate
        ontology_rank = LinkedData::Models::Ontology.rank
        docs = {}
        acronyms_ids = {}

        page_data.each do |doc|
          resource_id = doc["resource_id"]
          id = doc["submissionId_i"]
          acronym = doc["ontology_acronym_text"]
          old_resource_id = acronyms_ids[acronym]
          old_id = old_resource_id.split('/').last.to_i rescue 0

          already_found = (old_id && id && (id <= old_id))
          not_restricted = (doc["ontology_viewingRestriction_t"]&.eql?('public') || current_user&.admin?)
          user_not_restricted = not_restricted ||
            Array(doc["ontology_viewingRestriction_txt"]).any? {|u| u.split('/').last == current_user&.username} ||
            Array(doc["ontology_acl_txt"]).any? {|u| u.split('/').last == current_user&.username}

          user_restricted = !user_not_restricted

          if acronym.blank? || already_found || user_restricted
            total_found -= 1
            next
          end

          docs.delete(old_resource_id)
          acronyms_ids[acronym] = resource_id

          doc["ontology_rank"] = ontology_rank.dig(doc["ontology_acronym_text"], :normalizedScore) || 0.0
          docs[resource_id] = doc
        end

        docs = docs.values

        docs.sort! { |a, b| [b["score"], b["ontology_rank"]] <=> [a["score"], a["ontology_rank"]] } unless params[:sort].present?

        page = page_object(docs, total_found)

        reply 200, page
      end

      get '/content' do
        query = params[:query] || params[:q]
        page, page_size = page_params

        ontologies = params.fetch("ontologies", "").split(',')

        unless current_user&.admin?
          restricted_acronyms = restricted_ontologies_to_acronyms(params)
          ontologies = ontologies.empty? ? restricted_acronyms : ontologies & restricted_acronyms
        end

        types = params.fetch("types", "").split(',')
        qf = params.fetch("qf", "")

        qf = [
          "ontology_t^100 resource_id^10",
          "http___www.w3.org_2004_02_skos_core_prefLabel_txt^30",
          "http___www.w3.org_2004_02_skos_core_prefLabel_t^30",
          "http___www.w3.org_2000_01_rdf-schema_label_txt^30",
          "http___www.w3.org_2000_01_rdf-schema_label_t^30",
        ].join(' ') if qf.blank?

        fq = []

        fq << ontologies.map { |x| "ontology_t:\"#{x}\"" }.join(' OR ') unless ontologies.blank?
        fq << types.map { |x| "type_t:\"#{x}\" OR type_txt:\"#{x}\"" }.join(' OR ') unless types.blank?


        conn = SOLR::SolrConnector.new(Goo.search_conf, :ontology_data)
        resp = conn.search(query, fq: fq, qf: qf, defType: "edismax",
                           start: (page - 1) * page_size, rows: page_size)

        total_found = resp["response"]["numFound"]
        docs = resp["response"]["docs"]

        reply 200, page_object(docs, total_found)
      end
    end

  end
end