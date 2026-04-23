require 'haml'

class HomeController < ApplicationController

  namespace "/" do

    get do
      expires 3600, :public
      last_modified @@root_last_modified ||= Time.now.httpdate
      routes = routes_list
      routes_hash = {}
      context = {}
      routes.each do |route|
        next if route.length < 3 || route.split("/").length > 2
        route_no_slash = route.gsub("/", "")
        mapped_class = route_to_class_map[route]
        mapped_type_uri = safe_type_uri(mapped_class)
        context[route_no_slash] = mapped_type_uri.to_s unless mapped_type_uri.nil?
        routes_hash[route_no_slash] = LinkedData.settings.rest_url_prefix+route_no_slash
      end
      routes_hash["@context"] = context
      reply ({links: routes_hash})
    end

    get "documentation" do
      @metadata_all = metadata_all.sort {|a,b| a[0].name <=> b[0].name}
      haml "documentation/documentation".to_sym, :layout => "documentation/layout".to_sym
    end

    get "metadata/:class" do
      @metadata = metadata(params["class"])
      if @metadata.nil?
        error 404, "'#{params["class"]}' is not a documented media type. See /documentation or try /metadata/Ontology."
      end
      haml "documentation/metadata".to_sym, :layout => "documentation/layout".to_sym
    end

  end
end
