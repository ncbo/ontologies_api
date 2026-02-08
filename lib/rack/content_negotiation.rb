module Rack
  class ContentNegotiation
    DEFAULT_CONTENT_TYPE = "application/n-triples" # N-Triples
    VARY = { 'Vary' => 'Accept' }.freeze
    ENDPOINTS_FILTER = %r{^/ontologies/[^/]+/resolve/[^/]+$} # Accepted API endpoints to apply content negotiation

    # @return [#call]
    attr_reader :app

    # @return [Hash{Symbol => String}]
    attr_reader :options

    ##
    # @param  [#call]                  app
    # @param  [Hash{Symbol => Object}] options
    #   Other options passed to writer.
    # @option options [String] :default (DEFAULT_CONTENT_TYPE) Specific content type
    # @option options [RDF::Format, #to_sym] :format Specific RDF writer format to use
    def initialize(app, options = {})
      @app, @options = app, options
      @options[:default] = (@options[:default] || DEFAULT_CONTENT_TYPE).to_s
    end

    ##
    # Handles a Rack protocol request.
    # Parses Accept header to find appropriate mime-type and sets content_type accordingly.
    #
    # Inserts ordered content types into the environment as `ORDERED_CONTENT_TYPES` if an Accept header is present
    #
    # @param  [Hash{String => String}] env
    # @return [Array(Integer, Hash, #each)] Status, Headers and Body
    # @see    https://rubydoc.info/github/rack/rack/file/SPEC
    def call(env)
      if env['PATH_INFO'].match?(ENDPOINTS_FILTER)
        if env.has_key?('HTTP_ACCEPT')
          accepted_types = parse_accept_header(env['HTTP_ACCEPT'])
          if !accepted_types.empty?
            env["format"] = accepted_types.first
            add_content_type_header(app.call(env), env["format"])
          else
            not_acceptable
          end
        else
          env["format"] = options[:default]
          add_content_type_header(app.call(env), env["format"])
        end
      else
        app.call(env)
      end
    end

    protected

    # Parses an HTTP `Accept` header, returning an array of MIME content types ordered by precedence rules.
    #
    # @param  [String, #to_s] header
    # @return [Array<String>] Array of content types sorted by precedence
    # @see    https://www.w3.org/Protocols/rfc2616/rfc2616-sec14.html#sec14.1
    def parse_accept_header(header)
      entries = header.to_s.split(',')
      parsed_entries = entries.map { |entry| parse_accept_entry(entry) }
      sorted_entries = parsed_entries.sort_by { |entry| entry.quality }.reverse
      content_types = sorted_entries.map { |entry| entry.content_type }
      content_types.flatten.compact
    end



    # Parses an individual entry from the Accept header.
    #
    # @param [String] entry An entry from the Accept header
    # @return [Entry] An object representing the parsed entry
    def parse_accept_entry(entry)
      # Represents an entry parsed from the Accept header
      entry_struct = Struct.new(:content_type, :quality, :wildcard_count, :param_count)
      content_type, *params = entry.split(';').map(&:strip)
      quality = 1.0 # Default quality
      params.reject! do |param|
        if param.start_with?('q=')
          quality = param[2..-1].to_f
          true
        end
      end
      wildcard_count = content_type.count('*')
      entry_struct.new(content_type, quality, wildcard_count, params.size)
    end


    ##
    # Returns a content type appropriate for the given `media_range`,
    # returns `nil` if `media_range` contains a wildcard subtype
    # that is not mapped.
    #
    # @param  [String, #to_s] media_range
    # @return [String, nil]
    def find_content_type_for_media_range(media_range)
      case media_range.to_s
      when '*/*', 'text/*'
        options[:default]
      when 'application/n-triples'
        'application/n-triples'
      when 'text/turtle'
        'text/turtle'
      when 'application/json', 'application/ld+json', 'application/*'
        'application/ld+json'
      when 'text/xml', 'text/rdf+xml',  'application/rdf+xml', 'application/xml'
        'application/rdf+xml'
      else
        nil
      end
    end

    ##
    # Outputs an HTTP `406 Not Acceptable` response.
    #
    # @param  [String, #to_s] message
    # @return [Array(Integer, Hash, #each)]
    def not_acceptable(message = nil)
      code = 406
      http_status =  [code, Rack::Utils::HTTP_STATUS_CODES[code]].join(' ')
      message = http_status + (message.nil? ? "\n" : " (#{message})\n")
      [code, { 'Content-Type' => "text/plain" }.merge(VARY), [message]]
    end

    def add_content_type_header(response, type)
      response[1] = response[1].merge(VARY).merge('Content-Type' => type)
      response
    end

  end
end
