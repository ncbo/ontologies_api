class AnnotatorController < ApplicationController
  namespace "/annotator" do

    get "/recognizers" do
      reply [] unless Annotator.settings.enable_recognizer_param
      recognizers = []
      ObjectSpace.each_object(Annotator::Models::NcboAnnotator.singleton_class).each do |c|
        next if c == Annotator::Models::NcboAnnotator
        recognizer = c.name.downcase.split("::").last
        recognizers << recognizer if Annotator.settings.supported_recognizers.include?(recognizer.to_sym)
      end
      reply recognizers
    end

    post do
      process_annotation
    end

    get do
      process_annotation
    end

    # execute an annotator query
    def process_annotation(params=nil)
      validate_params_solr_population(Sinatra::Helpers::SearchHelper::ALLOWED_INCLUDES_PARAMS)
      params ||= @params
      params_copy = params.dup

      text = params_copy.delete("text")
      error 400, 'A text to be annotated must be supplied using the argument text=<text to be annotated>' if text.nil? || text.strip.empty?

      acronyms = restricted_ontologies_to_acronyms(params_copy)
      params_copy.delete("ontologies")
      semantic_types = semantic_types_param(params_copy)
      params_copy.delete("semantic_types")
      expand_class_hierarchy = params_copy.delete("expand_class_hierarchy").eql?('true')  # default = false
      class_hierarchy_max_level = params_copy.delete("class_hierarchy_max_level").to_i  # default = 0
      use_semantic_types_hierarchy = params_copy.delete("expand_semantic_types_hierarchy").eql?('true')  # default = false
      longest_only = params_copy.delete("longest_only").eql?('true')  # default = false
      expand_with_mappings = params_copy.delete("expand_mappings").eql?('true')  # default = false
      exclude_nums = params_copy.delete("exclude_numbers").eql?('true')  # default = false
      whole_word_only = params_copy.delete("whole_word_only").eql?('false') ? false : true  # default = true
      min_term_size = params_copy.delete("minimum_match_length").to_i    # default = 0
      exclude_synonyms = params_copy.delete("exclude_synonyms").eql?('true')  # default = false
      recognizer = (Annotator.settings.enable_recognizer_param && params_copy["recognizer"]) || 'mgrep'
      params_copy.delete("recognizer")

      annotator = nil

      # see if a name of the recognizer has been passed in, use default if not or error
      begin
        recognizer = recognizer.capitalize
        clazz = "Annotator::Models::Recognizers::#{recognizer}".split('::').inject(Object) {|o, c| o.const_get c}
        annotator = clazz.new
      rescue
        annotator = Annotator::Models::Recognizers::Mgrep.new
      end

      if params_copy["stop_words"]
        annotator.stop_words = params_copy.delete("stop_words")
      end

      params_copy.delete("display")
      options = {
        ontologies: acronyms,
        semantic_types: semantic_types,
        use_semantic_types_hierarchy: use_semantic_types_hierarchy,
        filter_integers: exclude_nums,
        expand_class_hierarchy: expand_class_hierarchy,
        expand_hierarchy_levels: class_hierarchy_max_level,
        expand_with_mappings: expand_with_mappings,
        min_term_size: min_term_size,
        whole_word_only: whole_word_only,
        with_synonyms: !exclude_synonyms,
        longest_only: longest_only
      }
      options = params_copy.symbolize_keys().merge(options)

      begin
        annotations = annotator.annotate(text, options)

        unless includes_param.empty?
          # Move include param to special param so it only applies to classes
          params["include_for_class"] = includes_param
          params.delete("display")
          params.delete("include")
          env["rack.request.query_hash"] = params

          orig_classes = annotations.map {|a| [a.annotatedClass, a.hierarchy.map {|h| h.annotatedClass}, a.mappings.map {|m| m.annotatedClass}]}.flatten
          classes_hash = populate_classes_from_search(orig_classes, acronyms)
          annotations = replace_empty_classes(annotations, classes_hash) do |a|
            replace_empty_classes(a.hierarchy, classes_hash)
            replace_empty_classes(a.mappings, classes_hash)
          end
        end
      rescue LinkedData::Models::Ontology::ParsedSubmissionError => e
        error 404, e.message
      rescue Annotator::Models::NcboAnnotator::BadSemanticTypeError => e
        error 404, e.message
      end

      reply 200, annotations
    end

    post '/dictionary' do
      admin_only!
      annotator = Annotator::Models::NcboAnnotator.new
      annotator.generate_dictionary_file()
    end

    post '/cache' do
      admin_only!
      delete_cache = params['delete_cache'].eql?('true')
      annotator = Annotator::Models::NcboAnnotator.new
      annotator.create_term_cache(nil, delete_cache)
    end

    private

    def get_page_params(text, args={})
      return args
    end

    ##
    # Take an array of annotations and replace 'empty' classes with populated ones
    # Does a lookup in a provided hash that uses ontology uri + class id as a key
    def replace_empty_classes(empty, populated_hash, &block)
      populated = []
      empty.each do |ann|
        yield ann, populated if block_given?
        found = replace_empty_class(ann, populated_hash)
        populated << ann if found
      end
      populated
    end

    def replace_empty_class(ann, populated)
      populated_cls = populated[ann.annotatedClass.submission.ontology.id.to_s + ann.annotatedClass.id.to_s]
      return false unless populated_cls
      ann.instance_variable_set("@annotatedClass", populated_cls)
      return true
    end

  end
end

