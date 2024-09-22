require 'sinatra/base'

module Sinatra
  module Helpers
    module BatchHelper

      # @param [Hash] class_id_by_ontology A hash with ontology ids as keys and lists of class ids as values
      # EX: {"http://data.bioontology.org/ontologies/SNOMEDCT" => ["http://blah1", "http://blah2", "http://blah3"]}
      def batch_class_lookup(class_id_by_ontology, goo_include)
        if class_id_by_ontology.is_a?(Array)
          class_id_by_ontology = convert_class_array(class_id_by_ontology)
        end
        latest_submissions = []
        all_class_ids = []
        all_latest = retrieve_latest_submissions
        all_latest_by_id = Hash.new
        all_latest.each do |acr,obj|
          all_latest_by_id[obj.ontology.id.to_s] = obj
        end
        class_id_to_ontology = Hash.new
        class_id_by_ontology.keys.each do |ont_id_orig|
          ont_id = ont_id_orig
          ont_id = LinkedData::Models::Base.replace_url_prefix_to_id(ont_id_orig.to_s)

          if all_latest_by_id[ont_id]
            latest_submissions << all_latest_by_id[ont_id]
            all_class_ids << class_id_by_ontology[ont_id_orig]
            class_id_by_ontology[ont_id_orig].each do |cls_id|
              class_id_to_ontology[cls_id] = ont_id_orig
            end
          end
        end
        all_class_ids.flatten!
        if latest_submissions.length == 0 or all_class_ids.length == 0
          return []
        else
          all_class_ids.uniq!
          all_class_ids.map! { |x| RDF::URI.new(x) }
          ont_classes = LinkedData::Models::Class.in(latest_submissions).ids(all_class_ids).include(goo_include).all

          to_reply = []
          ont_classes.each do |cls|
            if class_id_to_ontology[cls.id.to_s]
              ont_id_orig = class_id_to_ontology[cls.id.to_s]
              ont_id = LinkedData::Models::Base.replace_url_prefix_to_id(ont_id_orig.to_s)
              if all_latest_by_id[ont_id]
                cls.submission = all_latest_by_id[ont_id]
                to_reply << cls
              end
            end
          end
          return to_reply
        end
      end

      private

      def convert_class_array(classes)
        class_id_by_ontology = {}
        sample_class = classes.first.respond_to?(:klass) ? classes.first.klass : classes.first.class
        return class_id_by_ontology unless sample_class == LinkedData::Models::Class
        classes.each do |cls|
          ont = cls.submission.ontology.id.to_s
          class_id_by_ontology[ont] ||= []
          class_id_by_ontology[ont] << cls.id.to_s
        end
        class_id_by_ontology
      end

    end
  end
end

helpers Sinatra::Helpers::BatchHelper
