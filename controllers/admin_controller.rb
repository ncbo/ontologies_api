require 'multi_json'

class AdminController < ApplicationController

  namespace "/admin" do
    before {
      if LinkedData.settings.enable_security && (!env["REMOTE_USER"] || !env["REMOTE_USER"].admin?)
        error 403, "Access denied"
      end
    }

    # TODO: remove this endpoint. It's termporary to test the update check functionality
    # get "/latestversion" do
    #   iid = params["iid"]
    #   ver = params["version"]
    #
    #   latest_ver_info = {
    #       update_version: "2.5RC3", #"2.6RC1",
    #       update_available: true,
    #       notes: "blah blah and more"
    #   }
    #   reply MultiJson.dump latest_ver_info
    # end

    get "/update_info" do
      um = NcboCron::Models::UpdateManager.new
      um.check_for_update if params["force_check"].eql?('true')
      reply um.update_info
    end

    get "/update_check_enabled" do
      reply NcboCron.settings.enable_update_check ? 'true' : 'false'
    end

    get "/objectspace" do
      GC.start
      gdb_objs = Hash.new 0
      ObjectSpace.each_object {|o| gdb_objs[o.class] += 1}
      obj_usage = gdb_objs.to_a.sort {|a,b| b[1]<=>a[1]}
      MultiJson.dump obj_usage
    end

    get "/ontologies/:acronym/log" do
      ont_report = NcboCron::Models::OntologiesReport.new.ontologies_report(false)
      log_path = ont_report[:ontologies].has_key?(params["acronym"].to_sym) ? "#{LinkedData.settings.repository_folder}/#{ont_report[:ontologies][params["acronym"].to_sym][:logFilePath]}" : ''
      log_contents = ''

      if !log_path.empty? && File.file?(log_path)
        file = File.open(log_path, "rb")
        log_contents = file.read
        file.close
      end
      reply log_contents
    end

    put "/ontologies/:acronym" do
      actions = NcboCron::Models::OntologySubmissionParser::ACTIONS.dup
      actions[:all] = false
      error_message = "You must provide valid action(s) for ontology processing. Valid actions: ?actions=#{actions.keys.join(",")}"
      actions_param = params["actions"]
      error 404, error_message unless actions_param
      action_arr = actions_param.split(",")
      actions.each { |k, _| actions[k] = action_arr.include?(k.to_s) ? true : false }
      error 404, error_message if actions.values.select { |v| v === true }.empty?
      ont = Ontology.find(params["acronym"]).first
      error 404, "You must provide a valid `acronym` to retrieve an ontology" if ont.nil?
      ont.bring(:acronym, :submissions)
      latest = ont.latest_submission(status: :any)
      error 404, "Ontology #{params["acronym"]} contains no submissions" if latest.nil?
      check_last_modified(latest)
      latest.bring(*OntologySubmission.goo_attrs_to_load(includes_param))
      NcboCron::Models::OntologySubmissionParser.new.queue_submission(latest, actions)
      halt 204
    end

    get "/:acronym/latest_submission" do
      ont = Ontology.find(params["acronym"]).first
      error 404, "You must provide a valid `acronym` to retrieve an ontology" if ont.nil?
      include_status = params["include_status"]
      ont.bring(:acronym, :submissions)
      if include_status
        latest = ont.latest_submission(status: include_status.to_sym)
      else
        latest = ont.latest_submission(status: :any)
      end
      check_last_modified(latest) if latest
      latest.bring(*OntologySubmission.goo_attrs_to_load(includes_param)) if latest
      reply(latest || {})
    end

    get "/ontologies_report" do
      suppress_error = params["suppress_error"].eql?('true') # default = false
      reply NcboCron::Models::OntologiesReport.new.ontologies_report(suppress_error)
    end

    post "/ontologies_report" do
      ontologies = ontologies_param_to_acronyms(params)
      args = {name: "ontologies_report", message: "refreshing ontologies report"}
      process_id = process_long_operation(900, args) do |args|
        NcboCron::Models::OntologiesReport.new.refresh_report(ontologies)
      end
      reply(process_id: process_id)
    end

    get "/ontologies_report/:process_id" do
      process_id = MultiJson.load(redis.get(params["process_id"]))

      if process_id.nil?
        error 404, "Process id #{params["process_id"]} does not exit"
      else
        if process_id === "done"
          reply NcboCron::Models::OntologiesReport.new.ontologies_report(false)
        else
          # either "processing" OR errors {errors: ["errorA", "errorB"]}
          reply process_id
        end
      end
    end

    post "/clear_goo_cache" do
      redis_goo.flushdb
      halt 204
    end

    post "/clear_http_cache" do
      redis_http.flushdb
      halt 204
    end

    namespace "/search" do
      get '/collections' do
        conn = SOLR::SolrConnector.new(Goo.search_conf, '')
        collections =  { collections: conn.fetch_all_collections}
        reply(200, collections)
      end

      get '/collections/:collection/schema' do
        collection = params[:collection].to_sym
        conn = SOLR::SolrConnector.new(Goo.search_conf, collection)
        collection_schema = conn.fetch_schema

        reply(200, collection_schema)
      end

      post '/collections/:collection/schema/init' do
        collection = params[:collection].to_sym
        conn = SOLR::SolrConnector.new(Goo.search_conf, collection)
        collection_schema = conn.init_schema
        reply(200, collection_schema)
      end

      post '/collections/:collection/search' do
        collection = params[:collection].to_sym

        search_keys = %w[defType fq qf sort start rows fl stopwords lowercaseOperators]

        search_params = params.select { |key, _|  search_keys.include?(key) }
        search_query = params[:query] || params[:q]
        search_query = search_query.blank? ? '*' : search_query
        conn = SOLR::SolrConnector.new(Goo.search_conf, collection)
        reply(200, conn.search(search_query, search_params).to_h)
      end

      post '/index_batch/:model_name' do
        error 500, "model_name parameter not set" if params["model_name"].blank?

        model = Goo.model_by_name(params["model_name"].to_sym)
        error 500, "#{params["model_name"]} is not indexable" if model.nil? || !model.index_enabled?

        all_attrs = get_attributes_to_include([:all], model)

        collections = model.where.include(all_attrs).all
        indexed = []
        not_indexed = []
        collections.each do |m|
          begin
            response = m.index.dig("responseHeader", "status")
            if response.eql?(0)
              indexed << m.id
            else
              not_indexed << m.id
            end
          rescue StandardError
            not_indexed << m.id
          end
        end

        if !indexed.empty?
          msg = "Batch indexing for #{model.model_name} completed for"

          if not_indexed.empty?
            msg +=  " all models"
          else
            msg +=  " #{indexed.join(', ')} and not for the following #{not_indexed.join(', ')}, see logs for more details"
          end
          reply(200, msg)
        else
          reply(500, "Batch indexing for #{model.model_name} failed")
        end
      end
    end

    private

    def redis_goo
      Redis.new(host: LinkedData.settings.goo_redis_host, port: LinkedData.settings.goo_redis_port, timeout: 30)
    end

    def redis_http
      Redis.new(host: LinkedData.settings.http_redis_host, port: LinkedData.settings.http_redis_port, timeout: 30)
    end

  end
end
