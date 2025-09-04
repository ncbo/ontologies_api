require 'multi_json'

class ValidateOntologyFileController < ApplicationController
  namespace "/validate_ontology_file" do
    post do
      error 422, "Must provide ontology file using `ontology_file` field" unless params["ontology_file"]
      ontfilename = params["ontology_file"][:filename]
      process_id = "#{Time.now.to_i}_#{ontfilename}"
      redis.setex process_id, 360, MultiJson.dump("processing")
      proc = Proc.new {
        buf = StringIO.new
        log = Logger.new(buf)
        tmpdir = Dir.tmpdir
        ontfile = params["ontology_file"][:tempfile]
        parser = LinkedData::Parser::OWLAPICommand.new(ontfile.path, tmpdir, logger: log)
        error = []
        begin
          missing_imports = parser.call_owlapi_java_command[1]
        rescue => e
          puts "Parsing in validator failed: #{e.message}"
        ensure
          buf.rewind
          error_lines = buf.read.split("\n")
          error = extract_error_message(error_lines, format(ontfilename))
          ontfile.close
        end
        error.unshift("Could not download imports: #{missing_imports.join(",")}") if missing_imports && !missing_imports.empty?
        redis.setex process_id, 360, MultiJson.dump(error || [])
      }

      fork = true # set to false for testing
      if fork
        pid = Process.fork do
          proc.call
        end
        Process.detach(pid)
      else
        proc.call
      end

      reply(process_id: process_id)
    end

    get "/:process_id" do
      errors = MultiJson.load(redis.get(params["process_id"]))
      if errors.nil?
        error 404, "Process id #{params["process_id"]} does not exit"
      else
        reply errors
      end
    end

    private

    ERROR_FORMAT_MAP = {
      "obo" => ["org.semanticweb.owlapi.oboformat.OBOFormatOWLAPIParser"],
      "owl" => [
        "org.semanticweb.owlapi.rdf.rdfxml.parser.RDFXMLParser",
        "org.semanticweb.owlapi.owlxml.parser.OWLXMLParser",
        "org.semanticweb.owlapi.functional.parser.OWLFunctionalSyntaxOWLParser",
        "org.semanticweb.owlapi.manchestersyntax.parser.ManchesterOWLSyntaxOntologyParser"
      ],
      "unknown" => ["org.bioontology.UnknownParseError"]
    }
    def extract_error_message(error_lines, format)
      found_error = error_lines.any? {|l| l.downcase.include?("severe: problem parsing file")}
      if found_error
        errors = parse_errors(error_lines)
        if format && ERROR_FORMAT_MAP.key?(format)
          errors = Hash[(ERROR_FORMAT_MAP[format] || []).map {|err| [err, errors[err]]}]
        end
      end
      errors
    end

    ALLOWED_PARSERS = Set.new([
      "org.semanticweb.owlapi.rdf.rdfxml.parser.RDFXMLParser",
      "org.semanticweb.owlapi.owlxml.parser.OWLXMLParser",
      "org.semanticweb.owlapi.functional.parser.OWLFunctionalSyntaxOWLParser",
      "org.semanticweb.owlapi.manchestersyntax.parser.ManchesterOWLSyntaxOntologyParser",
      "org.semanticweb.owlapi.oboformat.OBOFormatOWLAPIParser"
    ])

    def parse_errors(error_lines)
      errors = {}
      errored = false
      error_lines.length.times do |i|
        line = error_lines[i]
        next if line.nil? || line.empty?
        errored = true if line.include?("Could not parse ontology")
        break if line.include?("org.stanford.ncbo.oapiwrapper.OntologyParser internalParse")
        parser = line.match(/Parser: (.*)@/)
        next unless parser && ALLOWED_PARSERS.include?(parser[1])
        error = []
        error_lines[i+1..-1].each do |error_message|
          next if error_message.nil? || error_message.empty?
          break if error_message.strip.start_with?("-------------------------") ||
            error_message.include?("org.stanford.ncbo.oapiwrapper.OntologyParser internalParse")
          error << error_message.strip
        end
        errors[parser[1]] = error
      end

      if errored && errors.length == 0
        errors["org.bioontology.UnknownParseError"] = "There is an unknown problem that caused the ontology to fail to parse"
      end

      errors
    end


    def format(filename)
      return nil if !filename.include?(".")
      filename.split(".").last.downcase
    end
  end
end