require 'sinatra/base'

module Sinatra
  module Helpers
    module InstancesHelper
      def label_regex_filter
        (Goo::Filter.new(:label).regex(@params["search"])) if is_set?(@params["search"])
      end

      def filter_classes_by(class_uri)
        class_uri.nil? ? nil : { types: RDF::URI.new(class_uri.to_s) }
      end
    end
  end
end

helpers Sinatra::Helpers::InstancesHelper