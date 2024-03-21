require 'sinatra/base'

module Sinatra
  module Helpers
    module InstancesHelper

      # TODO: generalize this to all routes (maybe in application_helper)
      def settings_params
        page, size = page_params
        attributes = get_attributes_to_include(includes_param)
        order_by = get_order_by_from(@params)
        bring_unmapped = bring_unmapped?(includes_param)
        filter_by_label = label_regex_filter

        [attributes, page, size, filter_by_label, order_by, bring_unmapped]
      end

      def is_set?(param)
        !param.nil? && param != ""
      end

      def label_regex_filter
        (Goo::Filter.new(:label).regex(@params["search"])) if is_set?(@params["search"])
      end

      def filter_classes_by(class_uri)
        class_uri.nil? ? nil :{types: RDF::URI.new(class_uri.to_s)}
      end

      def get_order_by_from(params , default_sort = :label , default_order = :asc)
        {(params["sortby"] || default_sort).to_sym => params["order"] || default_order} if is_set?(@params["sortby"])
      end

      def get_attributes_to_include(includes_param)
        ld = LinkedData::Models::Instance.goo_attrs_to_load(includes_param)
        ld.delete(:properties)
        ld
      end

      def bring_unmapped?(includes_param)
        (includes_param && includes_param.include?(:all))
      end

      def bring_unmapped_to(page_data, sub)
        LinkedData::Models::Instance.in(sub).models(page_data).include(:unmapped).all
      end

    end
  end
end

helpers Sinatra::Helpers::InstancesHelper