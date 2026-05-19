require 'sinatra/base'
require 'multi_json'
require 'uri'

module Sinatra
  module Helpers
    module PropertiesSearchHelper
      ALLOWED_INCLUDES_PARAMS = [:label, :labelGenerated, :definition, :parents].freeze
      PROPERTY_TYPES_PARAM = "property_types"

      def get_properties_search_query(text, params)
        validate_params_solr_population(ALLOWED_INCLUDES_PARAMS)

        # raise error if text is empty
        if text.nil? || text.strip.empty?
          raise error 400, "The search query must be provided via /property_search?q=<query>[&page=<pagenum>&pagesize=<pagesize>]"
        end

        query = ""
        params["defType"] = "edismax"
        params["stopwords"] = "true"
        params["lowercaseOperators"] = "true"
        params["fl"] = "*,score"
        params[SearchHelper::INCLUDE_VIEWS_PARAM] = params[SearchHelper::ALSO_SEARCH_VIEWS] if params[SearchHelper::ALSO_SEARCH_VIEWS]

        # highlighting is used to determine the field that got matched
        params["hl"] = "on"
        params["hl.simple.pre"] = SearchHelper::MATCH_HTML_PRE
        params["hl.simple.post"] = SearchHelper::MATCH_HTML_POST

        if params[SearchHelper::EXACT_MATCH_PARAM] == "true"
          query = "\"#{solr_escape(text)}\""
          params["qf"] = "resource_id^20 labelExact^10 labelGeneratedExact^8"
          params["hl.fl"] = "resource_id labelExact labelGeneratedExact"
        else
          params["qf"] = "labelExact^100 labelGeneratedExact^80 labelSuggestEdge^50 labelSuggestNgram label labelGenerated resource_id"
          query = solr_escape(text)
          # double quote the query if it is a URL (ID searches)
          query = "\"#{query}\"" if text =~ /\A#{URI::regexp(['http', 'https'])}\z/
        end

        params["ontologies"] = params["ontology_acronyms"].join(",") if params["ontology_acronyms"] && !params["ontology_acronyms"].empty?
        ontology_types = params[SearchHelper::ONTOLOGY_TYPES_PARAM].nil? || params[SearchHelper::ONTOLOGY_TYPES_PARAM].empty? ? [] : params[SearchHelper::ONTOLOGY_TYPES_PARAM].split(",").map(&:strip)
        onts = restricted_ontologies(params)

        onts.select! { |o| ont_type = o.ontologyType.nil? ? "ONTOLOGY" : o.ontologyType.get_code_from_id; ontology_types.include?(ont_type) } unless ontology_types.empty?
        acronyms = restricted_ontologies_to_acronyms(params, onts)
        filter_query = get_terms_field_query_param(acronyms, "submissionAcronym")
        # No acronym restriction: provide Solr's match-all literal so the
        # subsequent `filter_query << " AND <clause>"` appends produce a
        # well-formed `fq` instead of starting with a stray AND.
        filter_query = "*:*" if filter_query.empty?

        ontology_types_clause = ontology_types.empty? ? "" : get_quoted_field_query_param(ontology_types, "OR", "ontologyType")
        filter_query = "#{filter_query} AND #{ontology_types_clause}" unless (ontology_types_clause.empty?)

        filter_query << " AND definition:[* TO *]" if params[SearchHelper::REQUIRE_DEFINITIONS_PARAM] == "true"

        property_types = params[PROPERTY_TYPES_PARAM].nil? || params[PROPERTY_TYPES_PARAM].empty? ? [] : params[PROPERTY_TYPES_PARAM].split(",").map(&:strip)
        property_types_clause = property_types.empty? ? "" : get_quoted_field_query_param(property_types.map { |pt| pt.upcase }, "OR", "propertyType")
        filter_query = "#{filter_query} AND #{property_types_clause}" unless (property_types_clause.empty?)

        params["fq"] = filter_query
        params["q"] = query
        query
      end

      def property_object_instance(type)
        Object.const_get("LinkedData::Models::#{type.capitalize}Property")
      end

    end
  end
end

helpers Sinatra::Helpers::PropertiesSearchHelper
