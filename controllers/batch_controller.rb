class BatchController < ApplicationController
  namespace "/batch" do
    post do "/"
      fix_batch_params_for_request()
      resource_type = "http://www.w3.org/2002/07/owl#Class"
      unless params.key?(resource_type)
        error 422, "Batch endpoint only support calls to owl:Class resources"
      end
      batch_params = params[resource_type]
      incl = batch_params["include"].split(",").map {|e| e.to_sym}
      collection = batch_params["collection"]
      error 422, "Call should contain 'include' parameters" if incl.nil?
      error 422, "Call should contain 'collection' parameter" if collection.nil? || collection.length == 0
      goo_include = LinkedData::Models::Class.goo_attrs_to_load(incl)
      class_id_by_ontology = {}
      collection.each do |class_input|
        class_id_by_ontology[class_input["ontology"]] = [] unless class_id_by_ontology.include? class_input["ontology"]
        class_id_by_ontology[class_input["ontology"]] << class_input["class"]
      end
      classes = []
      total_time = 0
      threads = []
      mutex = Mutex.new
      class_id_by_ontology.keys.length.times do
        class_id_by_ontology.keys.each do |ont_id|
          class_ids = class_id_by_ontology.delete(ont_id)
          threads << Thread.new do
            ont_id = ont_id.sub(LinkedData.settings.rest_url_prefix, Goo.id_prefix)
            class_ids.uniq!
            class_ids.map! { |id| RDF::URI.new(id) }
            ont = LinkedData::Models::Ontology.find(RDF::URI.new(ont_id))
                        .include(submissions: [:submissionId]).first
            error 404, "Ontology #{ont_id} could not be found" if ont.nil?
            latest = ont.latest_submission
            latest.bring(ontology:[:acronym])
            ont_classes = LinkedData::Models::Class.in(latest).ids(class_ids).include(goo_include).all
            mutex.synchronize { classes.concat(ont_classes) }
          end
        end
      end
      threads.each{|t| t.join}
      reply({ resource_type => classes })
    end

    private

    def fix_batch_params_for_request
      batch_include = []
      @params.each {|resource_type, values| batch_include << values["include"]}
      batch_include.compact!
      @params["include"] = batch_include.join(",")
      env["rack.request.query_hash"] = @params
    end

  end
end
