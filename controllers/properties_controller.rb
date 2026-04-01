class PropertiesController < ApplicationController

  namespace "/ontologies/:ontology/properties" do

    get do
      props = nil
      ont, submission = get_ontology_and_submission

      begin
        props = ont.properties(submission)
      rescue LinkedData::Models::Ontology::ParsedSubmissionError => e
        error 404, e.message
      end

      reply props
    end

    get '/roots' do
      ont, submission = get_ontology_and_submission
      roots = ont.property_roots(submission, extra_include=[:hasChildren])
      reply 200, roots
    end

    get '/:property' do
      prop = params[:property]
      ont, submission = get_ontology_and_submission
      bring_unmapped = bring_unmapped?(includes_param)
      p = ont.property(prop, submission, display_all_attributes: bring_unmapped)
      error 404, "Property #{prop} not found in ontology #{ont.id.to_s}" if p.nil?
      reply 200, p
    end

    get '/:property/label' do
      expires 86400, :public
      ont, submission = get_ontology_and_submission
      query_label = <<eso
SELECT *
FROM #{submission.id.to_ntriples}
WHERE {
<#{params[:property]}> <http://www.w3.org/2000/01/rdf-schema#label> ?label }
 LIMIT 1
eso
      epr = Goo.sparql_query_client(:main)
      label = nil
      graphs = [submission.id]
      epr.query(query_label, graphs: graphs, query_options: {rules: :NONE}).each do |sol|
        label = sol[:label].object
      end
      reply({ label: label })
    end

    get '/:property/tree' do
      prop = params[:property]
      ont, submission = get_ontology_and_submission
      p = ont.property(prop, submission, display_all_attributes: false)
      error 404, "Property #{prop} not found in ontology #{ont.id.to_s}" if p.nil?
      root_tree = p.tree

      #add the other roots to the response
      roots = ont.property_roots(submission, extra_include=[:hasChildren])

      # if this path' root does not get returned by the ont.property_roots call, manually add it
      roots << root_tree unless roots.map { |r| r.id }.include?(root_tree.id)

      roots.each_index do |i|
        r = roots[i]

        if r.id == root_tree.id
          roots[i] = root_tree
        else
          roots[i].instance_variable_set("@children",[])
          roots[i].loaded_attributes << :children
        end
      end

      reply 200, roots
    end

    # Get all ancestors for given property
    get '/:property/ancestors' do
      prop = params[:property]
      ont, submission = get_ontology_and_submission
      p = ont.property(prop, submission, display_all_attributes: false)
      error 404, "Property #{prop} not found in ontology #{ont.id.to_s}" if p.nil?
      ancestors = p.ancestors
      p.class.in(submission).models(ancestors).include(:label, :definition).all

      reply 200, ancestors
    end

    # Get all descendants for given property
    get '/:property/descendants' do
      prop = params[:property]
      ont, submission = get_ontology_and_submission
      p = ont.property(prop, submission, display_all_attributes: false)
      error 404, "Property #{prop} not found in ontology #{ont.id.to_s}" if p.nil?
      descendants = p.descendants
      p.class.in(submission).models(descendants).include(:label, :definition).all

      reply 200, descendants
    end

    # Get all parents of given property
    get '/:property/parents' do
      prop = params[:property]
      ont, submission = get_ontology_and_submission
      p = ont.property(prop, submission, display_all_attributes: false)
      error 404, "Property #{prop} not found in ontology #{ont.id.to_s}" if p.nil?

      p.bring(:parents)
      reply [] if p.parents.empty?

      p.class.in(submission).models(p.parents).include(:label, :definition).all
      parents = p.parents.select { |x| !x.id.to_s["owl#{p.class::TOP_PROPERTY}"] }
      parents = p.class.sort_properties(parents)

      reply 200, parents
    end

    # Get all children of given property
    get '/:property/children' do
      prop = params[:property]
      ont, submission = get_ontology_and_submission
      p = ont.property(prop, submission, display_all_attributes: false)
      error 404, "Property #{prop} not found in ontology #{ont.id.to_s}" if p.nil?

      p.bring(:children)
      reply [] if p.children.empty?

      children = p.class.in(submission).models(p.children).include(:label, :definition).all
      children.each { |c| c.load_has_children }
      children = p.class.sort_properties(children)

      reply 200, children
    end

  end

end
