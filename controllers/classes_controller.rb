class ClassesController < ApplicationController

  namespace "/ontologies/:ontology/classes" do

    # Display a page for all classes
    get do
      includes_param_check
      ont, submission = get_ontology_and_submission
      cls_count = submission.class_count(LOGGER)
      error 403, "Unable to display classes due to missing metrics for #{submission.id.to_s}. Please contact the administrator." if cls_count < 0

      attributes, page, size, order_by_hash, bring_unmapped_needed = settings_params(LinkedData::Models::Class)
      check_last_modified_segment(LinkedData::Models::Class, [ont.acronym])

      index = LinkedData::Models::Class.in(submission)
      if order_by_hash
        index = index.order_by(order_by_hash)
        cls_count = nil
        # Add index here when, indexing fixed
        # index_name = 'classes_sort_by_date'
        # index = index.index_as(index_name)
        # index = index.with_index(index_name)
      end

      page_data = index
      page_data = page_data.include(attributes).page(page, size).page_count_set(cls_count).all
      reply page_data
    end

    # Get root classes using a paginated mode
    get '/roots_paged' do
      includes_param_check
      ont, submission = get_ontology_and_submission
      check_last_modified_segment(LinkedData::Models::Class, [ont.acronym])
      load_attrs = LinkedData::Models::Class.goo_attrs_to_load(includes_param)
      unmapped = load_attrs.delete(:properties)
      page, size = page_params

      roots = submission.roots(load_attrs, page, size, concept_schemes: concept_schemes, concept_collections: concept_collections)

      if unmapped && roots.length > 0
        LinkedData::Models::Class.in(submission).models(roots).include(:unmapped).all
      end
      reply roots
    end

    # Get root classes
    get '/roots' do
      params ||= @params
      includes_param_check
      ont, submission = get_ontology_and_submission
      check_last_modified_segment(LinkedData::Models::Class, [ont.acronym])
      load_attrs = LinkedData::Models::Class.goo_attrs_to_load(includes_param)
      unmapped = load_attrs.delete(:properties)
      load_attrs += LinkedData::Models::Class.concept_is_in_attributes if submission.skos?

      request_display(load_attrs.join(','))

      sort = params["sort"].eql?('true') || params["sort"].eql?('1') # default = false

      if sort
        roots = submission.roots_sorted(load_attrs, concept_schemes: concept_schemes, concept_collections: concept_collections)
      else
        roots = submission.roots(load_attrs, concept_schemes: concept_schemes, concept_collections: concept_collections)
      end

      if unmapped && roots.length > 0
        LinkedData::Models::Class.in(submission).models(roots).include(:unmapped).all
      end
      reply roots
    end

    # Display a single class
    get '/:cls' do
      ont, submission = get_ontology_and_submission
      check_last_modified_segment(LinkedData::Models::Class, [ont.acronym])
      ld = LinkedData::Models::Class.goo_attrs_to_load(includes_param)

      load_children = ld.delete :children
      unless load_children
        load_children = ld.select { |x| x.instance_of?(Hash) && x.include?(:children) }
        if load_children
          ld = ld.select { |x| !(x.instance_of?(Hash) && x.include?(:children)) }
        end
      end

      unmapped = ld.delete(:properties) ||
                 (includes_param && includes_param.include?(:all))

      ld << :memberOf if includes_param.include?(:all)

      cls = get_class(submission, ld)
      if unmapped
        LinkedData::Models::Class.in(submission)
                                 .models([cls]).include(:unmapped).all
      end
      if includes_param.include?(:hasChildren)
        cls.load_has_children
      end
      if !load_children.nil? and load_children.length > 0
        LinkedData::Models::Class.partially_load_children([cls], 500, cls.submission)
        if includes_param.include?(:hasChildren)
          cls.children.each do |c|
            c.load_has_children
          end
        end
      end
      reply cls
    end

    # Get a paths_to_root view
    get '/:cls/paths_to_root' do
      includes_param_check
      ont, submission = get_ontology_and_submission
      check_last_modified_segment(LinkedData::Models::Class, [ont.acronym])
      ld = LinkedData::Models::Class.goo_attrs_to_load(includes_param)
      cls = get_class(submission, ld)
      reply cls.paths_to_root
    end

    # Get a tree view (returns the tree from the roots classes to the specified class)
    get '/:cls/tree' do
      params ||= @params
      includes_param_check
      sort = params["sort"].eql?('true') || params["sort"].eql?('1') # default = false
      # We override include values other than the following, user-provided include ignored
      ont, submission = get_ontology_and_submission
      check_last_modified_segment(LinkedData::Models::Class, [ont.acronym])
      cls = get_class(submission)
      display_attrs = [:prefLabel, :hasChildren, :children, :obsolete, :subClassOf]
      display_attrs += LinkedData::Models::Class.concept_is_in_attributes if submission.skos?
      request_display(display_attrs.join(','))
      extra_include = [:hasChildren, :isInActiveScheme, :isInActiveCollection]
      if sort
        roots = submission.roots_sorted(extra_include, concept_schemes: concept_schemes, concept_collections: concept_collections)
        root_tree = cls.tree_sorted(concept_schemes: concept_schemes, concept_collections: concept_collections, roots: roots)
        # add the other roots to the response
      else
        roots = submission.roots(extra_include, concept_schemes: concept_schemes, concept_collections: concept_collections)
        root_tree = cls.tree(concept_schemes: concept_schemes, concept_collections: concept_collections, roots: roots)
        # add the other roots to the response
      end

      # if this path' root does not get returned by the submission.roots call, manually add it
      roots << root_tree unless roots.map { |r| r.id }.include?(root_tree.id)

      roots.each_index do |i|
        r = roots[i]
        if r.id == root_tree.id
          roots[i] = root_tree
        else
          roots[i].instance_variable_set("@children", [])
          roots[i].loaded_attributes << :children
        end
      end
      reply roots
    end

    # Get all ancestors for given class
    get '/:cls/ancestors' do
      includes_param_check
      ont, submission = get_ontology_and_submission
      check_last_modified_segment(LinkedData::Models::Class, [ont.acronym])
      cls = get_class(submission)
      error 404 if cls.nil?
      ancestors = cls.ancestors
      LinkedData::Models::Class.in(submission).models(ancestors)
                               .include(:prefLabel, :synonym, :definition).all
      reply ancestors
    end

    # Get all descendants for given class
    get '/:cls/descendants' do
      includes_param_check
      ont, submission = get_ontology_and_submission
      check_last_modified_segment(LinkedData::Models::Class, [ont.acronym])
      page, size = page_params
      cls = get_class(submission, load_attrs = [])
      error 404 if cls.nil?
      ld = LinkedData::Models::Class.goo_attrs_to_load(includes_param)
      unmapped = ld.delete(:properties)
      page_data = cls.retrieve_descendants(page, size)
      LinkedData::Models::Class.in(submission).models(page_data)
                               .include(:prefLabel, :synonym, :definition).all
      if unmapped
        LinkedData::Models::Class.in(submission).models(page_data).include(:unmapped).all
      end
      page_data.delete_if { |x| x.id.to_s == cls.id.to_s }
      reply page_data
    end

    # Get all children of given class
    get '/:cls/children' do
      includes_param_check
      ont, submission = get_ontology_and_submission
      check_last_modified_segment(LinkedData::Models::Class, [ont.acronym])
      page, size = page_params
      cls = get_class(submission)
      error 404 if cls.nil?
      ld = LinkedData::Models::Class.goo_attrs_to_load(includes_param)
      ld += LinkedData::Models::Class.concept_is_in_attributes if submission.skos?
      request_display(ld.join(','))

      page_data = submission.children(cls, includes_param: includes_param, concept_schemes: concept_schemes,
                                      concept_collections: concept_collections, page: page, size: size)

      reply page_data
    end

    # Get all parents of given class
    get '/:cls/parents' do
      includes_param_check
      ont, submission = get_ontology_and_submission
      check_last_modified_segment(LinkedData::Models::Class, [ont.acronym])
      cls = get_class(submission)
      ld = LinkedData::Models::Class.goo_attrs_to_load(includes_param)
      unmapped = ld.delete(:properties)
      if ld.include?(:children)
        error 422, "The parents call does not allow children attribute to be included"
      end

      cls.bring(:parents)
      reply [] if cls.parents.length == 0

      aggregates = LinkedData::Models::Class.goo_aggregates_to_load(ld)
      parents_query = LinkedData::Models::Class.in(submission).models(cls.parents).include(ld)
      parents_query.aggregate(*aggregates) unless aggregates.empty?
      parents = parents_query.all

      if unmapped
        LinkedData::Models::Class.in(submission).models(cls.parents).include(:unmapped).all
      end
      reply cls.parents.select { |x| !x.id.to_s["owl#Thing"] }
    end

    private

    def includes_param_check
      if includes_param
        if includes_param.include?(:all)
          error(422, "all not allowed in include parameter for this endpoint")
        end
        if includes_param.include?(:ancestors) || includes_param.include?(:descendants)
          error(422,
                "in this endpoint ancestors and descendants are not allowed in include parameter")
        end
      end
    end

    def request_display(attrs)

      params["display"] = attrs
      params["serialize_nested"] = true # Override safety check and cause children to serialize

      # Make sure Rack gets updated
      req = Rack::Request.new(env)
      req.update_param("display", attrs)
      req.update_param("serialize_nested", true)
    end
  end
end
