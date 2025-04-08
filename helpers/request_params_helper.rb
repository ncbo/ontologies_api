require 'sinatra/base'

module Sinatra
  module Helpers
    module RequestParamsHelper

      def settings_params(klass)
        page, size = page_params
        attributes = get_attributes_to_include(includes_param, klass)
        order_by = get_order_by_from(@params)
        bring_unmapped = bring_unmapped?(includes_param)

        [attributes, page, size, order_by, bring_unmapped]
      end

      def page?
        !params[:page].nil?
      end

      def is_set?(param)
        !param.nil? && param != ""
      end

      def get_order_by_from(params, default_order = :asc)
        if is_set?(params['sortby'])
          orders = (params["order"] || default_order.to_s).split(',')
          out = params['sortby'].split(',').map.with_index do |param, index|
            sort_order_item(param, orders[index] || default_order)
          end
          out.to_h
        end
      end

      def get_attributes_to_include(includes_param, klass)
        ld = klass.goo_attrs_to_load(includes_param)
        ld.delete(:properties)
        ld
      end

      def bring_unmapped?(includes_param)
        (includes_param && includes_param.include?(:all))
      end

      def reject_restricted_params!(params, model_class)
        return unless model_class.respond_to?(:hypermedia_settings)

        restricted = model_class.hypermedia_settings[:system_controlled]
        return if restricted.nil? || restricted.empty?

        forbidden = params.keys.map(&:to_sym) & restricted
        return if forbidden.empty?

        error 400, "Invalid request: You cannot set restricted attributes: #{forbidden.join(', ')}"
      end

      private
      def sort_order_item(param, order)
        [param.to_sym, order.to_sym]
      end
    end
  end
end

helpers Sinatra::Helpers::RequestParamsHelper
