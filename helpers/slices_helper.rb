require 'sinatra/base'
require 'ontologies_linked_data/models/slice'

module Sinatra
  module Helpers
    module SlicesHelper

      def filter_for_slice(obj)
        return obj unless LinkedData.settings.enable_slices
        return obj unless request.get? # only slice GET requests
        return obj unless slice_request?
        return obj unless obj.is_a?(Enumerable)

        first = obj.first
        return obj unless first && first.is_a?(LinkedData::Models::Ontology)

        slice = current_slice
        obj.select { |o| slice.ontology_id_set.include?(o.id.to_s) }
      end

      def slice_request?
        env['ncbo.slice'] && !LinkedData::Models::Slice.find(env['ncbo.slice']).first.nil?
      end

      def current_slice
        LinkedData::Models::Slice.find(env['ncbo.slice']).include(LinkedData::Models::Slice.attributes).first
      end

      def current_slice_acronyms
        return unless slice_request?
        current_slice.bring(ontologies: [:acronym])
        current_slice.ontologies.map {|o| o.acronym}
      end
    end
  end
end

helpers Sinatra::Helpers::SlicesHelper
