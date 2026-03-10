require 'sinatra/base'
require 'multi_json'

module Sinatra
  module Helpers
    module SearchHelper
      ALLOWED_INCLUDES_PARAMS = [:prefLabel, :synonym, :definition, :notation, :cui, :semanticType, :properties].freeze
      ONTOLOGIES_PARAM = "ontologies"
      ONTOLOGY_PARAM = "subtree_ontology"
      EXACT_MATCH_PARAM = "require_exact_match"
      INCLUDE_VIEWS_PARAM = "also_include_views"
      REQUIRE_DEFINITIONS_PARAM = "require_definitions"
      INCLUDE_PROPERTIES_PARAM = "also_search_properties"
      SUBTREE_ID_PARAM = "subtree_root_id"
      ALSO_SEARCH_OBSOLETE_PARAM = "also_search_obsolete"
      ALSO_SEARCH_PROVISIONAL_PARAM = "also_search_provisional"
      SUGGEST_PARAM = "suggest" # NCBO-932
      # the three below are for NCBO-1512, NCBO-1513, NCBO-1515
      VALUESET_ROOTS_ONLY_PARAM = "valueset_roots_only"
      VALUESET_EXCLUDE_ROOTS_PARAM = "valueset_exclude_roots"
      ONTOLOGY_TYPES_PARAM = "ontology_types"

      ALSO_SEARCH_VIEWS = "also_search_views" # NCBO-961
      MATCH_HTML_PRE = "<em>"
      MATCH_HTML_POST = "</em>"
      MATCH_TYPE_PREFLABEL = "prefLabel"
      MATCH_TYPE_SYNONYM = "synonym"
      MATCH_TYPE_PROPERTY = "property"
      MATCH_TYPE_LABEL = "label"
      MATCH_TYPE_LABELGENERATED = "labelGenerated"

      MATCH_TYPE_MAP = {
          "resource_id" => "id",
          MATCH_TYPE_PREFLABEL => MATCH_TYPE_PREFLABEL,
          "prefLabelExact" => MATCH_TYPE_PREFLABEL,
          "prefLabelSuggestEdge" => MATCH_TYPE_PREFLABEL,
          "prefLabelSuggestNgram" => MATCH_TYPE_PREFLABEL,
          MATCH_TYPE_SYNONYM => MATCH_TYPE_SYNONYM,
          "synonymExact" => MATCH_TYPE_SYNONYM,
          "synonymSuggestEdge" => MATCH_TYPE_SYNONYM,
          "synonymSuggestNgram" => MATCH_TYPE_SYNONYM,
          MATCH_TYPE_PROPERTY => MATCH_TYPE_PROPERTY,
          MATCH_TYPE_LABEL => MATCH_TYPE_LABEL,
          "labelExact" => MATCH_TYPE_LABEL,
          "labelSuggestEdge" => MATCH_TYPE_LABEL,
          "labelSuggestNgram" => MATCH_TYPE_LABEL,
          MATCH_TYPE_LABELGENERATED => MATCH_TYPE_LABELGENERATED,
          "labelGeneratedExact" => MATCH_TYPE_LABELGENERATED,
          "labelGeneratedSuggestEdge" => MATCH_TYPE_LABELGENERATED,
          "labelGeneratedSuggestNgram" => MATCH_TYPE_LABELGENERATED,
          "notation" => "notation",
          "cui" => "cui",
          "semanticType" => "semanticType"
      }

      # list of fields that allow empty query text
      QUERYLESS_FIELDS_PARAMS = {
          "ontologies" => nil,
          "notation" => "notation",
          "oboId" => "oboId",
          "cui" => "cui",
          "semantic_types" => "semanticType",
          ONTOLOGY_TYPES_PARAM => "ontologyType",
          ALSO_SEARCH_PROVISIONAL_PARAM => nil,
          SUBTREE_ID_PARAM => nil
      }

      QUERYLESS_FIELDS_STR = QUERYLESS_FIELDS_PARAMS.values.compact.join(" ")
      QUERYLESS_FIELDS_STR_NO_IDS = QUERYLESS_FIELDS_STR.gsub(/(notation|oboId)\s/, '')

      def get_term_search_query(text, params={})
        validate_params_solr_population(ALLOWED_INCLUDES_PARAMS)
        sort = params.delete('sort')
        # raise error if text is empty AND (none of the QUERYLESS_FIELDS_PARAMS has been passed
        # OR either an exact match OR suggest search is being executed)
        if text.nil? || text.strip.empty?
          if !QUERYLESS_FIELDS_PARAMS.keys.any? {|k| params.key?(k)} ||
              params[EXACT_MATCH_PARAM] == "true" ||
              params[SUGGEST_PARAM] == "true"
            raise error 400, "The search query must be provided via /search?q=<query>[&page=<pagenum>&pagesize=<pagesize>]"
          else
            text = ''
            params['sort'] = 'prefLabelExact asc, submissionAcronym asc' if sort == 'prefLabel'
          end
        end

        params["defType"] = "edismax"
        params["stopwords"] = "true"
        params["lowercaseOperators"] = "true"
        params["fl"] = "*,score"
        params[INCLUDE_VIEWS_PARAM] = params[ALSO_SEARCH_VIEWS] if params[ALSO_SEARCH_VIEWS]

        # highlighting is used to determine the field that got matched, NCBO-974
        params["hl"] = "on"
        params["hl.simple.pre"] = MATCH_HTML_PRE
        params["hl.simple.post"] = MATCH_HTML_POST

        if params[EXACT_MATCH_PARAM] == "true"
          query = "\"#{solr_escape(text)}\""
          params["qf"] = "resource_id^20 notation^20 oboId^20 #{add_lang_suffix('prefLabelExact', '^10')} #{add_lang_suffix('synonymExact')} #{QUERYLESS_FIELDS_STR_NO_IDS}"
          params["hl.fl"] = "resource_id #{add_lang_suffix('prefLabelExact')} #{add_lang_suffix('synonymExact')} #{QUERYLESS_FIELDS_STR}"
        elsif params[SUGGEST_PARAM] == "true" || text[-1] == '*'
          text.gsub!(/\*+$/, '')
          query = "\"#{solr_escape(text)}\""
          params["qt"] = "/suggest_ncbo"
          params["qf"] = [
            add_lang_suffix('prefLabelExact', '^100'),
            add_lang_suffix('prefLabelSuggestEdge', '^50'),
            add_lang_suffix('synonymSuggestEdge', '^10'),
            add_lang_suffix('prefLabelSuggestNgram'),
            add_lang_suffix('synonymSuggestNgram'),
            "resource_id #{QUERYLESS_FIELDS_STR}"
          ].join(' ')

          params["pf"] = add_lang_suffix('prefLabelSuggest', '^50')

          params["hl.fl"] = [
            add_lang_suffix('prefLabelExact'),
            add_lang_suffix('prefLabelSuggestEdge'),
            add_lang_suffix('synonymSuggestEdge'),
            add_lang_suffix('prefLabelSuggestNgram'),
            add_lang_suffix('synonymSuggestNgram'),
            "resource_id #{QUERYLESS_FIELDS_STR}"
          ].join(' ')
        else
          if text.strip.empty?
            query = '*'
          else
            query = solr_escape(text)
          end

          params["qf"] = [
            "resource_id^100",
            "notation^100",
            "oboId^100",
            add_lang_suffix('prefLabelExact', '^90'),
            add_lang_suffix('prefLabel', '^70'),
            add_lang_suffix('synonymExact', '^50'),
            add_lang_suffix('synonym', '^10'),
            QUERYLESS_FIELDS_STR_NO_IDS
          ].join(' ')

          params["qf"] << " property" if params[INCLUDE_PROPERTIES_PARAM] == "true"
          params["bq"] = "idAcronymMatch:true^80"
          params["hl.fl"] = "resource_id #{add_lang_suffix('prefLabelExact')} #{ add_lang_suffix('prefLabel')} #{add_lang_suffix('synonymExact')} #{add_lang_suffix('synonym')} #{QUERYLESS_FIELDS_STR}"
          params["hl.fl"] = "#{params["hl.fl"]} property" if params[INCLUDE_PROPERTIES_PARAM] == "true"
        end

        params[ONTOLOGIES_PARAM] = params["ontology_acronyms"].join(",") if params["ontology_acronyms"] && !params["ontology_acronyms"].empty?

        # sets ONTOLOGIES_PARM if subtree search is enabled
        # needs to be done BEFORE querying ontologies, but the
        # filter needs to be added AFTER the acronyms clause
        subtree_filter_query = subtree_filter_query(params)

        ontology_types = params[ONTOLOGY_TYPES_PARAM].nil? || params[ONTOLOGY_TYPES_PARAM].empty? ? [] : params[ONTOLOGY_TYPES_PARAM].split(",").map(&:strip)
        onts = restricted_ontologies(params)
        onts.select! { |o| ont_type = o.ontologyType.nil? ? "ONTOLOGY" : o.ontologyType.get_code_from_id; ontology_types.include?(ont_type) } unless ontology_types.empty?
        acronyms = restricted_ontologies_to_acronyms(params, onts)
        filter_query = get_terms_field_query_param(acronyms, "submissionAcronym")

        # add subtree filter query if not empty
        filter_query << subtree_filter_query

        # ontology types are required for CEDAR project to differentiate between ontologies and value set collections
        ontology_types_clause = ontology_types.empty? ? "" : get_quoted_field_query_param(ontology_types, "OR", "ontologyType")
        filter_query = "#{filter_query} AND #{ontology_types_clause}" unless (ontology_types_clause.empty?)

        # NCBO-1512, NCBO-1513, NCBO-1515 - CEDAR valueset requirements
        valueset_roots_only = params[VALUESET_ROOTS_ONLY_PARAM] || "false"
        valueset_exclude_roots = params[VALUESET_EXCLUDE_ROOTS_PARAM] || "false"

        if valueset_roots_only == "true" || valueset_exclude_roots == "true"
          valueset_root_ids = get_valueset_root_ids(onts, params)

          unless valueset_root_ids.empty?
            valueset_root_ids_clause = get_terms_field_query_param(valueset_root_ids, "resource_id")
            valueset_root_ids_clause = valueset_exclude_roots == "true" ? "AND -#{valueset_root_ids_clause}" : "AND #{valueset_root_ids_clause}"
            filter_query = "#{filter_query} #{valueset_root_ids_clause}"
          end
        end

        filter_query << " AND definition:[* TO *]" if params[REQUIRE_DEFINITIONS_PARAM] == "true"

        # NCBO-688 - by default search only non-obsolete classes
        also_search_obsolete = params[ALSO_SEARCH_OBSOLETE_PARAM] || "false"
        filter_query << " AND obsolete:false" if also_search_obsolete != "true"

        # NCBO-1418 - enable optional include of provisional classes
        also_search_provisional = params[ALSO_SEARCH_PROVISIONAL_PARAM] || "false"
        filter_query << " AND -provisional:true" if also_search_provisional != "true"

        # NCBO-695 - ability to search on CUI and TUI
        cui = cui_param(params)
        cui_clause = (cui.nil? || cui.empty?) ? "" : get_quoted_field_query_param(cui, "OR", "cui")
        filter_query = "#{filter_query} AND #{cui_clause}" unless (cui_clause.empty?)

        # NCBO-695 - ability to search on CUI and TUI (Semantic Type)
        semantic_types = semantic_types_param(params)
        semantic_types_clause = (semantic_types.nil? || semantic_types.empty?) ? "" : get_quoted_field_query_param(semantic_types, "OR", "semanticType")
        filter_query = "#{filter_query} AND #{semantic_types_clause}" unless (semantic_types_clause.empty?)

        params["fq"] = filter_query
        params["q"] = query

        query
      end

      def subtree_filter_query(params)
        filter_query = ""
        subtree_root_id = params[SUBTREE_ID_PARAM]

        if subtree_root_id
          ontology = params[ONTOLOGY_PARAM].nil? ? nil : params[ONTOLOGY_PARAM].split(",")

          if ontology.nil? || ontology.empty? || ontology.length > 1
            raise error 400, "A subtree search requires a single ontology: /search?q=<query>&ontology=CNO&subtree_id=http%3a%2f%2fwww.w3.org%2f2004%2f02%2fskos%2fcore%23Concept"
          end

          params[ONTOLOGIES_PARAM] = params[ONTOLOGY_PARAM]
          filter_query = " AND #{get_quoted_field_query_param([subtree_root_id], "", "parents")}"
        end
        filter_query
      end

      def add_matched_fields(solr_response, default_match)
        match = default_match
        all_matches = {}

        solr_response["highlighting"].each do |key, matches|
          largest_count = 0

          matches.each do |match_type, val|
            count = val[0].scan(MATCH_HTML_PRE).count

            if count > largest_count
              largest_count = count
              match = MATCH_TYPE_MAP[match_type]
            end
          end
          all_matches[key] = match
        end

        solr_response["match_types"] = all_matches
      end

      def portal_language
        Goo.main_languages.first
      end

      def request_languages
        lang = params['lang'] || params['languages']

        return [portal_language] if lang.blank?

        lang.split(',')
      end

      def request_multiple_languages?
        request_languages.size > 1 || request_all_languages?
      end

      def request_languages?
        !(params['lang'] || params['language']).blank?
      end

      def request_all_languages?
        request_languages.first.eql?('all')
      end

      def add_lang_suffix(attr, rank = "")
        if request_languages? && !request_all_languages?
          languages = request_languages
          languages.map { |lang| "#{attr}_#{lang}#{rank} " }.join
        else
          "#{attr}#{rank}"
        end
      end

      def pref_label_by_language(doc)
        Array(doc["prefLabel_#{request_languages.first}".to_sym]).first || Array(doc["prefLabel_none".to_sym]).first || Array(doc[:prefLabel]).first
      end

      def filter_attrs_by_language(doc)
        lang_values = {}
        doc.each do |k, v|
          attr, lang = k.to_s.split('_')

          next if [:ontology_rank, :resource_id, :resource_model].include?(k)
          next if lang.blank? || attr.blank?
          next if !(request_languages + %w[none]).include?(lang) && !request_all_languages?

          lang_values[attr.to_sym] ||= {}
          lang_values[attr.to_sym][lang] ||= []
          lang_values[attr.to_sym][lang] += v
        end

        if request_multiple_languages?
          lang_values.each do |k, lang_vals|
            doc[k] = lang_vals
          end
        else
          lang_values.each do |k, lang_vals|
            doc[k] = lang_vals.map { |l, v| l.eql?('none') ? nil : v }.compact.flatten + Array(lang_vals['none'])
          end

          doc[:prefLabel] =  pref_label_by_language(doc)
        end

        doc
      end

      # see https://github.com/rsolr/rsolr/issues/101
      # and https://github.com/projecthydra/active_fedora/commit/75b4afb248ee61d9edb56911b2ef51f30f1ce17f
      #
      def solr_escape(text)
        RSolr.solr_escape(text).gsub(/\s+/,"\\ ")
      end

      def get_valueset_root_ids(onts, params)
        root_ids = []
        also_search_provisional = params[ALSO_SEARCH_PROVISIONAL_PARAM] || "false"

        onts.each do |ont|
          next if ont.nil?
          ont.bring(:ontologyType) if ont.bring?(:ontologyType)
          next if ont.ontologyType.nil? || !ont.ontologyType.value_set_collection?
          submission = ont.latest_submission(status: [:RDF])
          next if submission.nil?

          roots = submission.roots
          root_ids_ont = roots.map {|d| d.id.to_s}
          root_ids << root_ids_ont

          if also_search_provisional == "true"
            prov_classes = LinkedData::Models::ProvisionalClass.where(ontology: ont).include(:subclassOf).all
            prov_class_ids = prov_classes.map {|c| c.id.to_s if c.subclassOf.nil?}
            root_ids.concat prov_class_ids
          end
        end
        root_ids.flatten
      end

      def get_tokenized_standard_query(text, params)
        words = text.split
        query = "("
        query << get_non_quoted_field_query_param(words, "prefLabel")
        query << " OR "
        query << get_non_quoted_field_query_param(words, "synonym")

        if params[INCLUDE_PROPERTIES_PARAM] == "true"
          query << " OR "
          query << get_non_quoted_field_query_param(words, "property")
        end
        query << ")"

        query
      end

      def get_quoted_field_query_param(words, clause, fieldName="")
        query = fieldName.empty? ? "" : "#{fieldName}:"

        if words.length > 1
          query << "("
        end
        query << "\"#{words[0]}\""

        if words.length > 1
          words[1..-1].each do |word|
            query << " #{clause} \"#{word}\""
          end
        end

        if words.length > 1
          query << ")"
        end

        query
      end

      def get_non_quoted_field_query_param(words, fieldName="")
        query = fieldName.empty? ? "" : "#{fieldName}:"
        query << words.join(" ")

        query
      end

      def get_terms_field_query_param(values, field_name)
        return "" if values.nil? || values.empty?

        escaped_values = values.map do |value|
          value.to_s.gsub('\\', '\\\\\\').gsub(',', '\\,').gsub('"', '\\"')
        end

        "_query_:\"{!terms f=#{field_name}}#{escaped_values.join(',')}\""
      end

      def set_page_params(params={})
        pagenum, pagesize = page_params(params)
        params["page"] = pagenum
        params["pagesize"] = pagesize
        params.delete("q")
        params.delete("ontologies")

        unless params["start"]
          if pagenum <= 1
            params["start"] = 0
          else
            params["start"] = pagenum * pagesize - pagesize
          end
        end
        params["rows"] ||= pagesize
      end

      ##
      # Populate an array of classes. Returns a hash where the key is ontology_uri + class_id:
      # "http://data.bioontology.org/ontologies/ONThttp://ont.org/class1" => cls
      def populate_classes_from_search(classes, ontology_acronyms=nil)
        class_ids = []
        acronyms = (ontology_acronyms.nil?) ? [] : ontology_acronyms
        classes.each {|c| class_ids << c.id.to_s; acronyms << c.submission.ontology.acronym.to_s unless ontology_acronyms}
        acronyms.uniq!
        old_classes_hash = Hash[classes.map {|cls| [cls.submission.ontology.id.to_s + cls.id.to_s, cls]}]
        params = {"ontology_acronyms" => acronyms}

        # Use a fake phrase because we want a normal wildcard query, not the suggest.
        # Replace this with a wildcard below.
        get_term_search_query("avoid_search_mangling", params)
        params.delete("ontology_acronyms")
        params.delete("q")
        params["qf"] = "resource_id"
        params["fq"] << " AND #{get_quoted_field_query_param(class_ids, "OR", "resource_id")}"
        params["rows"] = 99999
        # Replace fake query with wildcard
        resp = LinkedData::Models::Class.submit_search_query("*:*", params)

        classes_hash = {}
        resp["response"]["docs"].each do |doc|
          doc = doc.symbolize_keys
          resource_id = doc[:resource_id]
          doc.delete :resource_id
          doc[:id] = resource_id
          ontology_uri = doc[:ontologyId].sub(/\/submissions\/.*/, "")
          ont_uri_class_uri = ontology_uri + resource_id
          old_class = old_classes_hash[ont_uri_class_uri]
          next unless old_class
          doc[:submission] = old_class.submission
          doc[:properties] = MultiJson.load(doc.delete(:propertyRaw)) if include_param_contains?(:properties)
          instance = LinkedData::Models::Class.read_only(doc)
          instance.prefLabel = pref_label_by_language(doc)
          classes_hash[ont_uri_class_uri] = instance
        end

        classes_hash
      end

      def validate_params_solr_population(allowed_includes_params)
        leftover = includes_param - allowed_includes_params
        invalid = leftover.length > 0
        message = "The `include` query string parameter cannot accept #{leftover.join(", ")}, please use only #{allowed_includes_params.join(", ")}"
        error 400, message if invalid
      end

      def get_ontology_metadata_search_options(params)
        groups = params.fetch("groups", "").split(',')
        categories = params.fetch("hasDomain", "").split(',')
        languages = params.fetch("languages", "").split(',')
        status = params.fetch("status", "").split(',')
        format = params.fetch("hasOntologyLanguage", "").split(',')
        is_of_type = params.fetch("isOfType", "").split(',')
        has_format = params.fetch("hasFormat", "").split(',')
        visibility = params["visibility"]
        show_views = params["show_views"] == 'true'
        sort = params.fetch("sort", "score desc, ontology_name_sort asc, ontology_acronym_sort asc")
        page, page_size = page_params

        fq = [
          'resource_model:"ontology_submission"',
          'submissionStatus_txt:ERROR_* OR submissionStatus_txt:"RDF" OR submissionStatus_txt:"UPLOADED"',
          groups.map { |x| "ontology_group_txt:\"http://data.bioontology.org/groups/#{x.upcase}\"" }.join(' OR '),
          categories.map { |x| "ontology_hasDomain_txt:\"http://data.bioontology.org/categories/#{x.upcase}\"" }.join(' OR '),
          languages.map { |x| "naturalLanguage_txt:\"#{x.downcase}\"" }.join(' OR '),
        ]

        fq << "ontology_viewingRestriction_t:#{visibility}" unless visibility.blank?
        fq << "!ontology_viewOf_t:*" unless show_views

        fq << format.map { |x| "hasOntologyLanguage_t:\"http://data.bioontology.org/ontology_formats/#{x}\"" }.join(' OR ') unless format.blank?

        fq << status.map { |x| "status_t:#{x}" }.join(' OR ') unless status.blank?
        fq << is_of_type.map { |x| "isOfType_t:#{x}" }.join(' OR ') unless is_of_type.blank?
        fq << has_format.map { |x| "hasFormalityLevel_t:#{x}" }.join(' OR ') unless has_format.blank?

        fq.reject!(&:blank?)

        if params[:qf]
          qf = params[:qf]
        else
          qf = [
            "ontologySuggestEdge^25 ontology_acronymSuggestEdge^25  ontology_nameSuggestEdge^15 descriptionSuggestEdge^10 ", # start of the word first
            "ontology_t^15 ontology_acronym_text^15  ontology_name_text^10 description_text^5 ", # full word match
            "ontologySuggestNgram^2 ontology_acronymSuggestNgram^2 ontology_nameSuggestNgram^1.5 descriptionSuggestNgram" # substring match last
          ].join(' ')
        end

        options = {
          fq: fq,
          qf: qf,
          page: page,
          page_size: page_size,
          sort: sort
        }
        options
      end

      def get_query(params)
        if params[:query].nil? && params[:q].nil?
          raise error 400, "The search query must be provided via /search?q=<query>[&page=<pagenum>&pagesize=<pagesize>] /search?query=<query>[&page=<pagenum>&pagesize=<pagesize>]"
        end
        query = params[:query] || params[:q]
        query
      end

      def search(model, query, params = {})
        query = query.blank? ? "*" : query
        resp = model.search(query, search_params(**params))
        total_found = resp["response"]["numFound"]
        docs = resp["response"]["docs"]

        page_object(docs, total_found)
      end

      def search_params(defType: "edismax", fq:, qf:, stopwords: "true", lowercaseOperators: "true", page:, page_size:, fl: '*,score', sort:)
        {
          defType: defType,
          fq: fq,
          qf: qf,
          sort: sort,
          start: (page - 1) * page_size,
          rows: page_size,
          fl: fl,
          stopwords: stopwords,
          lowercaseOperators: lowercaseOperators,
        }
      end

      def process_search(params = nil)
        params ||= @params
        params['q'] ||= params['query']
        params.delete('query')
        text = params["q"]

        query = get_term_search_query(text, params)
        # puts "Edismax query: #{query}, params: #{params}"
        set_page_params(params)

        docs = Array.new
        resp = LinkedData::Models::Class.search(query, params)
        total_found = resp["response"]["numFound"]
        add_matched_fields(resp, Sinatra::Helpers::SearchHelper::MATCH_TYPE_PREFLABEL)
        ontology_rank = LinkedData::Models::Ontology.rank

        resp["response"]["docs"].each do |doc|
          doc = doc.symbolize_keys
          # NCBO-974
          doc[:matchType] = resp["match_types"][doc[:id]]
          resource_id = doc[:resource_id]
          doc.delete :resource_id
          doc[:id] = resource_id
          # TODO: The `rescue next` on the following line shouldn't be here
          # However, at some point we didn't store the ontologyId in the index
          # and these records haven't been cleared out so this is getting skipped
          ontology_uri = doc[:ontologyId].sub(/\/submissions\/.*/, "") rescue next
          ontology = LinkedData::Models::Ontology.read_only(id: ontology_uri, acronym: doc[:submissionAcronym])
          submission = LinkedData::Models::OntologySubmission.read_only(id: doc[:ontologyId], ontology: ontology)
          doc[:submission] = submission
          doc[:ontology_rank] = (ontology_rank[doc[:submissionAcronym]] && !ontology_rank[doc[:submissionAcronym]].empty?) ? ontology_rank[doc[:submissionAcronym]][:normalizedScore] : 0.0
          doc[:properties] = MultiJson.load(doc.delete(:propertyRaw)) if include_param_contains?(:properties)

          doc = filter_attrs_by_language(doc)

          instance = doc[:provisional] ? LinkedData::Models::ProvisionalClass.read_only(doc) : LinkedData::Models::Class.read_only(doc)
          docs.push(instance)
        end

        unless params['sort']
          if !text.nil? && text[-1] == '*'
            docs.sort! { |a, b| [b[:score], a[:prefLabelExact].downcase, b[:ontology_rank]] <=> [a[:score], b[:prefLabelExact].downcase, a[:ontology_rank]] }
          else
            docs.sort! { |a, b| [b[:score], b[:ontology_rank]] <=> [a[:score], a[:ontology_rank]] }
          end
        end

        page_object(docs, total_found)
      end

    end
  end
end

helpers Sinatra::Helpers::SearchHelper
