require 'sinatra/base'

module Sinatra
  module Helpers
    module SchemesHelper
      def schemes_setting_params
        ont, submission = get_ontology_and_submission
        attributes, page, size, filter_by_label, order_by, bring_unmapped_needed  =  settings_params(LinkedData::Models::SKOS::Scheme)
        [submission, attributes, bring_unmapped_needed]
      end

      def get_scheme_uri(params)
        scheme_uri = RDF::URI.new(params[:scheme])

        unless scheme_uri.valid?
          error 400, "The input scheme id '#{params[:scheme]}' is not a valid IRI"
        end
        scheme_uri
      end
    end
  end
end

helpers Sinatra::Helpers::SchemesHelper