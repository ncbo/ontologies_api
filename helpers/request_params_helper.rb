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

      def filter?
        is_set?(@params["filter_by"])
      end

      def filter
        build_filter
      end

      def apply_filters(object, query)
        attributes_to_filter = object.attributes(:all).select{|x| params.keys.include?(x.to_s)}
        filters = attributes_to_filter.map {|key| [key, params[key]&.split(',')]}.to_h
        add_direct_filters(filters, query)
      end

      def apply_submission_filters(query)

        filters = {
          naturalLanguage: params[:naturalLanguage]&.split(',') , #%w[http://lexvo.org/id/iso639-3/fra http://lexvo.org/id/iso639-3/eng],
          hasOntologyLanguage_acronym: params[:hasOntologyLanguage]&.split(',') , #%w[OWL SKOS],
          ontology_hasDomain_acronym:  params[:hasDomain]&.split(',') , #%w[Crop Vue_francais],
          ontology_group_acronym: params[:group]&.split(','), #%w[RICE CROP],
          isOfType: params[:isOfType]&.split(','), #["http://omv.ontoware.org/2005/05/ontology#Vocabulary"],
          hasFormalityLevel: params[:hasFormalityLevel]&.split(','), #["http://w3id.org/nkos/nkostype#thesaurus"],
          ontology_viewingRestriction: params[:viewingRestriction]&.split(','), #["private"]
          status: params[:status]&.split(','), #"retired",
        }
        inverse_filters = {
          submissionStatus: params[:submissionStatus] #"RDF",
        }

        query = add_direct_filters(filters, query)

        query = add_inverse_filters(inverse_filters, query)

        query = add_acronym_name_filters(query)

        add_order_by_patterns(query)
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

      def bring_unmapped_to(page_data, sub, klass)
        klass.in(sub).models(page_data).include(:unmapped).all
      end

      private
      def extract_attr(key)
        attr, sub_attr, sub_sub_attr = key.to_s.split('_')

        return attr.to_sym unless sub_attr

        return {attr.to_sym => [sub_attr.to_sym]} unless  sub_sub_attr

        {attr.to_sym => [sub_attr.to_sym => sub_sub_attr.to_sym]}
      end

      def add_direct_filters(filters, query)
        filters.each do |key, values|
          attr = extract_attr(key)
          next if Array(values).empty?

          filter = Goo::Filter.new(attr).regex(values.first)
          values.drop(1).each do |v|
            filter = filter.or(Goo::Filter.new(attr).regex(v))
          end
          query = query.filter(filter)
        end
        query
      end

      def add_inverse_filters(inverse_filters, query)
        inverse_filters.each do |key, value|
          attr = extract_attr(key)
          next unless value

          filter = Goo::Filter.new(attr).regex("^(?:(?!#{value}).)*$")
          query = query.filter(filter)
        end
        query
      end

      def add_acronym_name_filters(query)
        filters = {
          acronym: :ontology_acronym,
          name: :ontology_name,
          description: :description
        }.map do |key, attr|
          (params[key].nil? || params[key].empty?) ?  nil : [extract_attr(attr), params[key]]
        end.compact

        return  query if filters.empty?

        key, val = filters.first
        filter = Goo::Filter.new(key).regex(val)

        filters.drop(1).each do |k, v|
          filter = filter.or(Goo::Filter.new(k).regex(v))
        end

        query.filter(filter)
      end

      def add_order_by_patterns(query)
        if params[:order_by]
          attr, sub_attr = params[:order_by].to_s.split('_')
          if sub_attr
            order_pattern = { attr.to_sym => { sub_attr.to_sym => (sub_attr.eql?("name") ? :asc : :desc) } }
          else
            order_pattern = { attr.to_sym => :desc }
          end
          query = query.order_by(order_pattern)
        end
        query
      end

      def sort_order_item(param, order)
        [param.to_sym, order.to_sym]
      end

      def build_filter(value = @params["filter_value"])
        Goo::Filter.new(@params["filter_by"].to_sym).regex(value)
      end
    end
  end
end

helpers Sinatra::Helpers::RequestParamsHelper
