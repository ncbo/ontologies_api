class BatchController < ApplicationController


  namespace "/batch" do
    post do "/"
      if params.keys != ["http://www.w3.org/2002/07/owl#Class"]
        reply 422, "Batch endpoint only support calls to owl:Class resources"
      end
      resource_type = params.keys.first
      batch_params = params[resource_type]
      incl = batch_params["include"]
      collection = batch_params["collection"]
      reply 422, "Call should contain 'include' parameters" if incl.nil?
      reply 422, "Call should contain 'collection' parameter" if collection.nil? || collection.length == 0
      goo_include = LinkedData::Models::Class.goo_attrs_to_load(incl)
      class_id_by_ontology = {}
      collection.each do |class_input|
        class_id_by_ontology[class_input["ontology"]] = [] unless class_id_by_ontology.include? class_input["ontology"]
        class_id_by_ontology[class_input["ontology"]] << class_input["class"]
      end
      classes = []
      class_id_by_ontology.each do |ont_id,class_ids|
        class_ids.uniq!
        class_ids.map! { |id| RDF::URI.new(id) }
        ont = LinkedData::Models::Ontology.find(RDF::URI.new(ont_id))
                    .include(submissions: [:submissionId]).first
        latest = ont.latest_submission
        latest.bring(ontology:[:acronym])
        classes.concat(LinkedData::Models::Class.in(latest).ids(class_ids).include(goo_include.map{|x| x.to_sym}).read_only.all)
      end
      reply({ "http://www.w3.org/2002/07/owl#Class" => classes })
    end
  end
end
