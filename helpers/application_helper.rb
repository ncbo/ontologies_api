require 'sinatra/base'
require 'sinatra/namespace'
require 'multi_json'
require 'securerandom'
require 'date'
require 'rdf'
require 'uri'

module Sinatra
  module Helpers
    module ApplicationHelper

      ##
      # Escape text for use in html
      def h(text)
        Rack::Utils.escape_html(text)
      end

      ##
      # Populate +obj+ using values from +params+
      # Will also try to find related objects using a Goo lookup.
      # TODO: Currently, this allows for mass-assignment of everything, which will permit
      # users to overwrite any attribute, including things like passwords.
      def populate_from_params(obj, params)
        return if obj.nil?

        # Make sure everything is loaded
        if obj.is_a?(LinkedData::Models::Base)
          obj.bring_remaining if obj.exist?

          # Strip out attributes that aren't explicitly declared in the model
          no_writable_attributes = obj.class.attributes(:all) - obj.class.attributes
          params = params.reject { |k, v| no_writable_attributes.include? k.to_sym }

          # Strip out system_controlled attributes
          restricted = obj.class.hypermedia_settings[:system_controlled]
          params = params.reject { |k, _| restricted&.include?(k.to_sym) }

          # Handle special-case assignment of `creator`
          # Some models require a `creator` attribute (e.g., Notes, ProvisionalClass).
          # Historically this was provided by clients via request params,
          # but since `creator` is now treated as a system-controlled attribute,
          # it should be assigned internally (e.g., from `current_user`) and
          # must not be overwritten or user-defined.#
          assign_creator_if_applicable(obj)
        end
        params.each do |attribute, value|
          next if value.nil?

          # Deal with empty strings for String and URI
          empty_string = value.is_a?(String) && value.empty?
          old_string_value_exists = obj.respond_to?(attribute) && (obj.send(attribute).is_a?(String) || obj.send(attribute).is_a?(RDF::URI))
          old_string_value_exists ||= obj.respond_to?(attribute) && obj.send(attribute).is_a?(LinkedData::Models::Base)
          if old_string_value_exists && empty_string
            value = nil
          elsif empty_string
            next
          end

          attribute = attribute.to_sym
          attr_cls = obj.class.range(attribute)
          attribute_settings = obj.class.attribute_settings(attribute)

          not_hash_or_array = !value.is_a?(Hash) && !value.is_a?(Array)
          not_array_of_hashes = value.is_a?(Array) && !value.first.is_a?(Hash)

          if attr_cls == LinkedData::Models::Class
            # Try to find dependent Goo objects, but only if the naming is not done via Proc
            # If naming is done via Proc, then try to lookup the Goo object using a hash of attributes
            is_arr = value.is_a?(Array)
            value = is_arr ? value : [value]
            new_value = []
            value.each do |cls|
              if uri_as_needed(cls["ontology"]).nil?
                new_value << cls
                next
              end
              sub = LinkedData::Models::Ontology.find(uri_as_needed(cls["ontology"])).first.latest_submission
              new_value << LinkedData::Models::Class.find(cls["class"]).in(sub).first
            end
            value = is_arr ? new_value : new_value[0]
          elsif attr_cls && not_hash_or_array || (attr_cls && not_array_of_hashes)
            # Replace the initial value with the object, handling Arrays as appropriate
            if value.is_a?(Array)
              value = value.map { |e| attr_cls.find(uri_as_needed(e)).include(attr_cls.attributes).first }
            elsif !value.nil?
              value = attr_cls.find(uri_as_needed(value)).include(attr_cls.attributes).first
            end
          elsif attr_cls
            # Check to see if the resource exists in the triplestore
            if value.is_a?(Array)
              retrieved_values = []
              value.each do |e|
                e = e.to_h
                retrieved_value = attr_cls.where(e.symbolize_keys).first

                if retrieved_value
                  retrieved_values << retrieved_value
                else
                  val = populate_from_params(attr_cls.new, e.symbolize_keys)

                  if val.valid?
                    val.save
                    retrieved_values << val
                  end
                end
              end
            else
              retrieved_values = attr_cls.where(value.to_h.symbolize_keys).to_a

              unless retrieved_values
                val = populate_from_params(attr_cls.new, e.symbolize_keys)

                if val.valid?
                  val.save
                  retrieved_values = val
                end
              end
            end
            value = retrieved_values
          elsif attribute_settings && attribute_settings[:enforce] && attribute_settings[:enforce].include?(:date_time)
            # TODO: Remove this awful hack when obj.class.model_settings[:range][attribute] contains DateTime class
            is_array = value.is_a?(Array)
            value = Array(value).map { |v| DateTime.parse(v) }
            value = value.first unless is_array
            value
          elsif attribute_settings && attribute_settings[:enforce] && attribute_settings[:enforce].include?(:uri) && attribute_settings[:enforce].include?(:list)
            # in case its a list of URI, convert all value to IRI
            value = Array(value).map { |v| RDF::IRI.new(v) }
          elsif attribute_settings && attribute_settings[:enforce] && attribute_settings[:enforce].include?(:uri)
            # TODO: Remove this awful hack when obj.class.model_settings[:range][attribute] contains RDF::IRI class
            unless value.nil?
              # If pass an empty string for an URI : set it as nil.
              value = RDF::IRI.new(value)
            end
          end
          # Don't populate naming attributes if they exist
          if obj.class.model_settings[:name_with] != attribute || obj.send(attribute).nil?
            obj.send("#{attribute}=", value) if obj.respond_to?("#{attribute}=")
          end
        end
        obj
      end

      ##
      # Create an instance of +cls+ using provided +params+ to fill in attributes
      def instance_from_params(cls, params)
        n = cls.new
        populate_from_params(n, params)
      end

      ##
      # Serialize objects using a custom serializer that handles content negotiation
      # using the Accept header and "format" query string parameter
      # The method has two options parameters:
      #   +status (Fixnum)+: Status code to use in response
      #   +obj (Object)+: The object to serialize
      # Usage: +reply object+, +reply 201, object+
      def reply(*response)
        status = response.shift
        if !status.instance_of?(Integer)
          response.unshift status
          status = 200
        end

        obj = response.shift
        halt 404 if obj.nil?

        # Security check
        check_access(obj) if LinkedData.settings.enable_security

        # Slice or set check
        obj = filter_for_slice(obj) if LinkedData.settings.enable_slices

        # Check for custom ontologies set by user
        obj = filter_for_user_onts(obj)

        LinkedData::Serializer.build_response(@env, status: status, ld_object: obj)
      end

      ##
      # Override the halt method provided by Sinatra to set the response appropriately
      def halt(*response)
        status, headers, obj = nil
        obj = response.first if response.length == 1
        if obj.instance_of?(Integer)
          # This is a status-only response
          status = obj
          obj = nil
        end
        status, obj = response.first, response.last if response.length == 2
        status, headers, obj = response.first, response[1], response.last if response.length == 3
        if obj.is_a?(Rack::File) # Avoid the serializer when returning files
          super(response)
        else
          super(LinkedData::Serializer.build_response(@env, status: status, headers: headers, ld_object: obj))
        end
      end

      ##
      # Create an error response body by wrapping a message in a common hash structure
      # Call by providing an error code and then message or just a message:
      #   +error "Error message"+
      #   +error 400, "Error message"+
      def error(*message)
        status = message.shift
        if !status.instance_of?(Integer)
          message.unshift status
          status = 500
        end
        halt status, { :errors => message, :status => status }
      end

      ##
      # Look for the includes parameter and provide a formatted list of attributes
      def includes_param
        if @params["display"]
          return @params["display"].split(",").map {|e| e.to_sym}
        end
        Array.new
      end

      ##
      # Look for the ontologies acronym and give back a formatted list of ontolody id uris
      # This can be called without passing an argument and it will use the values from the current request
      def ontologies_param(params=nil)
        params ||= @params

        if params["ontologies"]
          # Get list
          ontologies = params["ontologies"].split(",").map {|o| o.strip}
          # When they aren't URIs, make them URIs
          ontologies.map! {|o| o.start_with?("http://") ? replace_url_prefix(o) : ontology_uri_from_acronym(o)}
          if ontologies.include? nil
            error 404, "The ontologies parameter `[#{params["ontologies"]}]` includes non-existent acronyms. Notice that acronyms are case sensitive."
          end
          return ontologies
        end
        Array.new
      end

      def restricted_ontologies(params=nil)
        params ||= @params

        found_onts = false
        if params["ontologies"] && !params["ontologies"].empty?
          onts = ontology_objects_from_params(params)
          found_onts = onts.length > 0
          Ontology.where.models(onts).include(*Ontology.access_control_load_attrs).all
        else
          onts = if params["also_include_views"] == "true"
            Ontology.where.include(Ontology.goo_attrs_to_load()).to_a
          else
            Ontology.where.filter(Goo::Filter.new(:viewOf).unbound).include(Ontology.goo_attrs_to_load()).to_a
                 end

          found_onts = onts.length > 0

          onts = filter_for_slice(onts)
          onts = filter_for_user_onts(onts)
        end
        onts = filter_access(onts)

        if found_onts && onts.empty?
          error 422, "No ontologies were found (either they weren't accessible to the user or there are none)"
        end

        return onts
      end

      def restricted_ontologies_to_acronyms(params=nil, onts=nil)
        onts ||= restricted_ontologies(params)
        return onts.map {|o| o.acronym }
      end

      def ontologies_param_to_acronyms(params=nil)
        ontResourceIds = ontologies_param(params)
        return ontResourceIds.map { |ontResourceId| ontResourceId.to_s.split('/')[-1]}
      end

      ##
      # Get semantic types parameter in the form [semantic_types=T099,T085,T345]
      def semantic_types_param(params=nil)
        params ||= @params

        if params["semantic_types"]
          semanticTypes = params["semantic_types"].split(",").map {|o| o.strip}
          return semanticTypes
        end
        Array.new
      end

      ##
      # Get cui parameter in the form [cui=C0302369,C0522224,C0176617]
      def cui_param(params=nil)
        params ||= @params
        if params["cui"]
          cui = params["cui"].split(",").map {|o| o.strip}
          return cui
        end
        Array.new
      end

      # validates month for 1-12 or 01-09
      def month_param(params=nil)
        params ||= @params
        if params["month"]
          month = params["month"].strip
          if %r{(?<month>^(0[1-9]|[1-9]|1[0-2])$)}x === month
            return month.to_i.to_s
          end
        end
        nil
      end

      # validates year for starting with 1 or 2 and containing 4 digits
      def year_param(params=nil)
        params ||= @params
        if params["year"]
          year = params["year"].strip
          if %r{(?<year>^([1-2]\d{3})$)}x === year
            return year.to_i.to_s
          end
        end
        nil
      end

      ##
      # Given an acronym (BRO), get the ontology URI (http://data.bioontology.org/ontologies/BRO)
      # @param acronym [String] the ontology acronym
      def ontology_uri_from_acronym(acronym)
        ontology_uri_acronym_map[acronym]
      end

      ##
      # Given a URI (http://data.bioontology.org/ontologies/BRO), get the ontology acronym (BRO)
      # @param uri [String] the ontology uri
      def acronym_from_ontology_uri(uri)
        acronym_ontology_uri_map[uri.to_s]
      end

      ##
      # Given an ontology acronym returns the ontology model.
      # Replies 404 if the ontology does not exist
      # Replies 400 if the ontology does not have a parsed submission
      def ontology_from_acronym(acronym)
        ontology = LinkedData::Models::Ontology.find(acronym).first
        error(404, "Ontology with acronym `#{acronym}` not found") if ontology.nil?
        submission = ontology.latest_submission
        error(400, "No parsed submissions for ontology with acronym `#{acronym}`") if submission.nil?
        return ontology
      end

      ##
      # From user params, return the ontology models.
      # Replies 404 if the ontology does not exist
      # Replies 400 if the ontology does not have a parsed submission
      def ontology_objects_from_params(params = nil)
        ontologies = Set.new(ontologies_param(params))
        all_onts = LinkedData::Models::Ontology.where.include(LinkedData::Models::Ontology.goo_attrs_to_load).to_a
        all_onts.select {|o| ontologies.include?(o.id.to_s)}
      end

      def ontology_uri_acronym_map
        cached_map = naive_expiring_cache_read(__method__)
        return cached_map if cached_map
        map = {}
        LinkedData::Models::Ontology.where.include(:acronym).all.each {|o| map[o.acronym] = o.id.to_s}
        naive_expiring_cache_write(__method__, map)
        map
      end

      def acronym_ontology_uri_map
        cached_map = naive_expiring_cache_read(__method__)
        return cached_map if cached_map
        map = {}
        LinkedData::Models::Ontology.where.include(:acronym).all.each {|o| map[o.id.to_s] = o.acronym}
        naive_expiring_cache_write(__method__, map)
        map
      end

      ##
      # Create a URI if the id is a URI, otherwise return unmodified
      def uri_as_needed(id)
        return id unless id.is_a?(String)
        id = replace_url_prefix(id)
        uri = RDF::URI.new(id)
        uri.valid? ? uri : id
      end

      def create_rdf_uri(uri)
        return uri if uri.class == RDF::URI

        # Attempt to parse the URI string
        parsed_uri = URI.parse(uri)

        # Check if the parsed URI has a valid scheme (e.g., http, https)
        if parsed_uri.scheme && parsed_uri.host
          # Return a new RDF::URI object if the URI is valid
          RDF::URI.new(uri)
        else
          # Return nil if there is no valid scheme or host
          nil
        end
      rescue URI::InvalidURIError
        # Return nil if the URI is not valid
        nil
      end

      ##
      # If the setting is enabled, replace the URL prefix with the proper id prefix
      # EX: http://stagedata.bioontology.org/ontologies/BRO would become http://data.bioontology.org/ontologies/BRO
      def replace_url_prefix(id)
        LinkedData::Models::Base.replace_url_prefix_to_id(id)
      end

      def get_ontology_and_submission
        ont = Ontology.find(@params["ontology"])
              .include(:acronym, :administeredBy, :acl, :viewingRestriction)
              .include(submissions:
                       [:submissionId, submissionStatus: [:code], ontology: [:acronym], metrics: :classes])
                .first
        error(404, "Ontology '#{@params["ontology"]}' not found.") if ont.nil?
        check_access(ont) if LinkedData.settings.enable_security # Security check
        submission = nil
        if @params.include? "ontology_submission_id"
          submission = ont.submission(@params[:ontology_submission_id])
          if submission.nil?
            error 404,
               "You must provide an existing submission ID for the #{@params["acronym"]} ontology"
          end
        else
          submission = ont.latest_submission(status: [:RDF])
        end
        error 404, "Ontology #{@params["ontology"]} submission not found." if submission.nil?
        if !submission.ready?(status: [:RDF])
          error 404, "Ontology #{@params["ontology"]} submission #{submission.submissionId} has not been parsed."
        end

        save_submission_language(submission)

        return ont, submission
      end

      def current_user
        env["REMOTE_USER"] || LinkedData::Models::User.new
      end

      def include_param_contains?(str)
        str = str.to_s unless str.is_a?(String)
        class_params_include = params["include_for_class"] && params["include_for_class"].include?(str.to_sym)
        params_include = params["display"] && params["display"].split(",").include?(str)
        return class_params_include || params_include
      end

      # Long-operation helper modeled after the original from AdminController#process_long_operation
      # Start: "processing"
      # Success (empty/nil): "done"
      # Success (payload): payload as-is (no status Hash)
      # Error: { errors: ["..."] }
      def process_long_operation(timeout, args = {}, &block)
        name = (args[:name] || "job").to_s.gsub(/\s+/, "_")
        message = (args[:message] || name).to_s
        process_id = "#{Time.now.to_i}-#{name}-#{SecureRandom.hex(4)}"

        # 1) Immediately mark processing
        redis.setex(process_id, timeout, MultiJson.dump("processing"))

        worker = proc do
          begin
            result = block.call(args)

            # 2) Success. Preserve legacy string based responses
            if result.nil? || (result.respond_to?(:empty?) && result.empty?)
              redis.setex(process_id, timeout, MultiJson.dump("done"))
            elsif result.is_a?(Hash) || result.is_a?(Array) || result.is_a?(String) || result.is_a?(Numeric) || result == true || result == false
              redis.setex(process_id, timeout, MultiJson.dump(result))
            else
              redis.setex(process_id, timeout, MultiJson.dump("done"))
            end
          rescue => e
            # 3) Error → log + legacy error payload (no backtrace to clients)
            msg = "Error #{message} - #{e.class}: #{e.message}"
            log_msg = "#{msg}\n#{e.backtrace.join("\n\t")}"
            if respond_to?(:logger) && logger
              logger.error(log_msg)
            else
              $stderr.puts(log_msg)
            end
            redis.setex(process_id, timeout, MultiJson.dump(errors: [msg]))
          end
        end

        # 4) Background work (toggle via fork: false in tests)
        fork_process = ENV['RACK_ENV'] != 'test'
        if fork_process
          pid = Process.fork { worker.call }
          Process.detach(pid)
        else
          worker.call
        end

        process_id
      end

      def redis
        Redis.new(host: Annotator.settings.annotator_redis_host, port: Annotator.settings.annotator_redis_port, timeout: 30)
      end

      private

      def naive_expiring_cache_write(key, object, timeout = 60)
        @naive_expiring_cache ||= {}
        @naive_expiring_cache[key] = {timeout: Time.now + timeout, object: object}
      end

      def naive_expiring_cache_read(key)
        return if @naive_expiring_cache.nil?
        object = @naive_expiring_cache[key]
        return if object.nil?
        return if Time.now > object[:timeout]
        return object[:object]
      end

      def save_submission_language(submission, language_property = :naturalLanguage)
        request_lang = RequestStore.store[:requested_lang]

        return if submission.nil? || !request_lang.blank?

        submission.bring(language_property) if submission.bring?(language_property)
        collection_natural_language = submission.send(language_property) rescue nil
        return [] if collection_natural_language.blank?

        collection_natural_language = collection_natural_language.values.flatten if collection_natural_language.is_a?(Hash)
        submissions_language = collection_natural_language.map { |natural_language| natural_language.to_s.split('/').last[0..1] }.compact.first

        RequestStore.store[:requested_lang] =  submissions_language if submissions_language
      end

      # Assigns the current user as the creator if:
      # - the model responds to `creator`,
      # - the attribute is marked system-controlled
      # - and the creator has not yet been set.
      # This must run after system-controlled params are stripped.
      def assign_creator_if_applicable(obj)
        return unless obj.respond_to?(:creator)
        return unless obj.creator.nil?

        restricted = obj.class.hypermedia_settings[:system_controlled]
        return unless restricted&.include?(:creator)

        obj.creator = current_user
      end
    end
  end
end

helpers Sinatra::Helpers::ApplicationHelper
