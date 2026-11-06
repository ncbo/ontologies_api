module Rack
  class ParamTranslator

    PARAM_MAP = {
        "include"                      => "display",
        "include_views"                => "also_include_views",
        "include_context"              => "display_context",
        "include_links"                => "display_links",
        "exact_match"                  => "require_exact_match",
        "suggest"                      => "enable_suggest",
        "require_definition"           => "require_definitions",
        "include_properties"           => "also_search_properties",
        "include_obsolete"             => "also_search_obsolete",
        "obsolete"                     => "also_search_obsolete",
        "ontology"                     => "subtree_ontology",
        "subtree_root"                 => "subtree_root_id",
        "subtree_id"                   => "subtree_root_id",
        "use_semantic_types_hierarchy" => "expand_semantic_types_hierarchy",
        "max_level"                    => "class_hierarchy_max_level",
        "mappings"                     => "expand_mappings",
        "include_synonyms"             => "exclude_synonyms",
        "with_synonyms"                => "exclude_synonyms",
        "include_classes"              => "display_classes",
        "expand_hierarchy"             => "expand_class_hierarchy"
    }

    def initialize(app = nil, options = {})
      @app = app
    end

    def call(env)
      r = Rack::Request.new(env)

      PARAM_MAP.each do |key, val|
        r.update_param(val, r.params[key]) if (r.params.has_key?(key) && !r.params.has_key?(val))
      end

      # The oLD serializer also reads `display`, so normalize it here rather than in includes_param.
      display = r.params["display"]
      if display.is_a?(Array) && display.all? { |v| v.is_a?(String) }
        r.update_param("display", display.join(","))
      elsif !display.nil? && !display.is_a?(String)
        return bad_request("The `include` parameter must be a comma-separated list, e.g. include=prefLabel,synonym")
      end

      if (!r.params["include_synonyms"].nil?)
        r.params["include_synonyms"] == "false" ? r.update_param("exclude_synonyms", "true") : r.update_param("exclude_synonyms", "false")
      elsif (!r.params["with_synonyms"].nil?)
        r.params["with_synonyms"] == "false" ? r.update_param("exclude_synonyms", "true") : r.update_param("exclude_synonyms", "false")
      end

      @app.call(env)
    end

    private

    def bad_request(message)
      body = MultiJson.dump({ errors: [message], status: 400 })
      [400, { "content-type" => "application/json", "content-length" => body.bytesize.to_s }, [body]]
    end

  end
end