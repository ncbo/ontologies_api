require 'sinatra/base'

module Sinatra
  module Helpers
    module CollectionsHelper
      def collections_setting_params
        ont, submission = get_ontology_and_submission
        attributes, page, size, filter_by_label, order_by, bring_unmapped_needed  =  settings_params(LinkedData::Models::SKOS::Collection)
        [submission, attributes, bring_unmapped_needed]
      end

      def get_collection_uri(params)
        collection_uri = RDF::URI.new(params[:collection])

        unless collection_uri.valid?
          error 400, "The input collection id '#{params[:collection]}' is not a valid IRI"
        end
        collection_uri
      end
    end
  end
end

helpers Sinatra::Helpers::CollectionsHelper