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

      def ontology_in_slice?(acronym)
        return true unless LinkedData.settings.enable_slices
        return true unless slice_request?

        slice = current_slice
        return true unless slice

        ont_id = LinkedData::Models::Ontology.id_from_unique_attribute(:acronym, acronym).to_s
        slice.ontology_id_set.include?(ont_id)
      end

      def slice_request?
        return env['ncbo.slice.is_request'] if env.key?('ncbo.slice.is_request')

        env['ncbo.slice.is_request'] = !!(env['ncbo.slice'] && current_slice)
      end

      def current_slice
        return env['ncbo.slice.object'] if env.key?('ncbo.slice.object')

        env['ncbo.slice.object'] = LinkedData::Models::Slice.find(env['ncbo.slice'])
                                     .include(LinkedData::Models::Slice.attributes).first
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
