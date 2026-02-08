use Rack::ContentNegotiation

class DereferenceResourceController < ApplicationController
  namespace "/ontologies" do
    get "/:acronym/resolve/:uri" do
      acronym = params[:acronym]
      uri = params[:uri]

      if acronym.blank? || uri.blank?
        error 500, "Usage: ontologies/:acronym/resolve/:uri?output_format= OR POST: acronym, uri, output_format parameters"
      end

      output_format = env["format"].presence || params[:output_format].presence || 'application/n-triples'

      process_request(acronym, uri, output_format)
    end

    private

    def process_request(acronym_param, uri_param, output_format)
      acronym = acronym_param
      uri = URI.decode_www_form_component(uri_param)

      error 500, "INVALID URI" unless valid_url?(uri)
      sub = LinkedData::Models::Ontology.find(acronym).first&.latest_submission

      error 500, "Ontology not found" unless  sub

      r = Resource.new(sub.id, uri)
      case output_format
      when 'application/ld+json', 'application/json'
          r.to_json
      when 'application/rdf+xml', 'application/xml'
          r.to_xml
      when 'text/turtle'
          r.to_turtle
      when 'application/n-triples'
          r.to_ntriples
      else
          error 500, "Invalid output format, valid format are: application/json, application/ld+json,  application/xml, application/rdf+xml, text/turtle and application/n-triples"
      end


    end

    def valid_url?(url)
      uri = URI.parse(url)
      uri.is_a?(URI::HTTP) || uri.is_a?(URI::HTTPS)
    rescue URI::InvalidURIError
      false
    end
  end
end