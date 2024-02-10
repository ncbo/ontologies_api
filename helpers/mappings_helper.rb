require 'sinatra/base'

module Sinatra
  module Helpers
    module MappingsHelper
      ##
      # Take an array of mappings and replace 'empty' classes with populated ones
      # Does a lookup in a provided hash that uses ontology uri + class id as a key
      def replace_empty_classes(mappings, populated_hash)
        mappings.each do |map|
          map.classes.each_with_index do |cls, i|
            found = populated_hash[cls.submission.ontology.id.to_s + cls.id.to_s]
            map.classes[i] = found if found
          end
        end
      end

      ##
      # Populate an arary of mappings with class data retrieved from search
      def populate_mapping_classes(mappings)
        return mappings if includes_param.empty?

        # Move include param to special param so it only applies to classes
        params["include_for_class"] = includes_param
        params.delete("display")
        params.delete("include")
        env["rack.request.query_hash"] = params

        orig_classes = mappings.map {|m| m.classes}.flatten.uniq
        acronyms = orig_classes.map {|c| c.submission.ontology.acronym}.uniq
        classes_hash = populate_classes_from_search(orig_classes, acronyms)
        replace_empty_classes(mappings, classes_hash)

        mappings
      end

      def request_mapping_id
        mapping_id = nil
        if params[:mapping] and params[:mapping].start_with?("http")
          mapping_id = RDF::URI.new(params[:mapping])
        else
          mapping_id =
            "http://data.bioontology.org/rest_backup_mappings/#{params[:mapping]}"
          mapping_id = RDF::URI.new(mapping_id)
        end
        mapping_id
      end
    end
  end
end

helpers Sinatra::Helpers::MappingsHelper