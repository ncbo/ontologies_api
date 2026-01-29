class BatchController < ApplicationController
  namespace "/batch" do
    post do
      fix_include_to_display()
      fix_batch_params_for_request()
      resource_type = "http://www.w3.org/2002/07/owl#Class"
      unless params.key?(resource_type)
        error 422, "Batch endpoint only support calls to owl:Class resources"
      end
      batch_params = params[resource_type]
      incl = batch_params["display"].split(",").map {|e| e.to_sym}
      collection = batch_params["collection"]
      error 422, "Call should contain 'include' parameters" if incl.nil?
      error 422, "Call should contain 'collection' parameter" if collection.nil? || collection.length == 0
      goo_include = LinkedData::Models::Class.goo_attrs_to_load(incl)
      class_id_by_ontology = {}
      collection.each do |class_input|
        unless class_input.is_a?(Hash)
          error 422, "The collection param needs to be { 'class' : CLS_ID, 'ontology' : ont_id }"
        end
        unless class_input.include?("ontology") and class_input.include?("class")
          error 422, "The collection param needs to be { 'class' : CLS_ID, 'ontology' : ont_id }"
        end
        unless class_id_by_ontology.include? class_input["ontology"]
          class_id_by_ontology[class_input["ontology"]] = []
        end
        class_id_by_ontology[class_input["ontology"]] << class_input["class"]
      end
      reply({ resource_type => batch_class_lookup(class_id_by_ontology, goo_include) })
    end

    private

    ##
    # Recursive method to change include to display
    # Can be removed when we finally stop supporting the `include` param
    def fix_include_to_display(params = nil)
      params ||= @params
      params.keys.each do |k|
        v = params[k]
        params["display"] = v if k.eql?("include")
        if v.is_a?(Hash)
          fix_include_to_display(v)
        end
      end
    end

    def fix_batch_params_for_request
      batch_include = []
      @params.each {|resource_type, values| batch_include << values["display"]}
      batch_include.compact!
      @params["display"] = batch_include.join(",")
      env["rack.request.query_hash"] = @params
    end

  end
end
