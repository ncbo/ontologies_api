require 'haml'
require 'redcarpet'

class HomeController < ApplicationController

  CLASS_MAP = {
      Property: "LinkedData::Models::ObjectProperty"
  }

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
        context[route_no_slash] = route_to_class_map[route].type_uri.to_s if route_to_class_map[route] && route_to_class_map[route].respond_to?(:type_uri)
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
      haml "documentation/metadata".to_sym, :layout => "documentation/layout".to_sym
    end

    def resource_collection_link(cls)
      resource = @metadata[:cls].name.split("::").last
      return "" if resource.nil?

      resource_path = "/" + resource.underscore.pluralize

      case
      when resource == "Class"
        "Example: "\
        "<a href='/ontologies/SNOMEDCT/classes/http%3A%2F%2Fpurl.bioontology.org%2Fontology%2FSNOMEDCT%2F410607006'>"\
        "/ontologies/SNOMEDCT/classes/http%3A%2F%2Fpurl.bioontology.org%2Fontology%2FSNOMEDCT%2F410607006</a>"
      when resource == "Instance"
        "Example: "\
        "<a href='/ontologies/CTX/classes/http%3A%2F%2Fwww.owl-ontologies.com%2FOntologyXCT.owl%23Eyelid/instances'>"\
        "/ontologies/CTX/classes/http%3A%2F%2Fwww.owl-ontologies.com%2FOntologyXCT.owl%23Eyelid/instances</a>"
      when resource == "Mapping"
        "Example: "\
        "<a href='/ontologies/SNOMEDCT/classes/http%3A%2F%2Fpurl.bioontology.org%2Fontology%2FSNOMEDCT%2F410607006/mappings'>"\
        "/ontologies/SNOMEDCT/classes/http%3A%2F%2Fpurl.bioontology.org%2Fontology%2FSNOMEDCT%2F410607006/mappings</a>"
      when resource == "Note"
        "Example: <a href='/ontologies/NCIT/notes'>/ontologies/NCIT/notes</a>"
      when resource == "OntologySubmission"
        "Example: "\
        "<a href='/ontologies/NCIT/submissions?display=submissionId,version'>"\
        "/ontologies/NCIT/submissions?display=submissionId,version</a>"
      when (routes_list().include? resource_path) == false
        "Example: coming soon"
      else
        "Resource collection: <a href='#{resource_path}'>#{resource_path}</a>"
      end
    end

    def metadata(cls)
      unless cls.is_a?(Class)
        cls = cls.singularize
        cls = LinkedData::Models.const_get(cls)
      end
      metadata_all[cls]
    end

    def sample_objects
      ontology = LinkedData::Models::Ontology.read_only(id: LinkedData.settings.rest_url_prefix+"/ontologies/BRO", acronym: "BRO")
      submission = LinkedData::Models::OntologySubmission.read_only(id: LinkedData.settings.rest_url_prefix+"/ontologies/BRO/submissions/1", ontology: ontology)
      cls = LinkedData::Models::Class.read_only(id: "http://bioontology.org/ontologies/BiomedicalResourceOntology.owl#Ontology_Development_and_Management", submission: submission)
      return {
        LinkedData::Models::Ontology.type_uri => ontology,
        LinkedData::Models::Class.type_uri => cls
      }
    end

    def metadata_all
      return @metadata_all_info if @metadata_all_info
      ld_classes = ObjectSpace.each_object(Class).select { |klass| klass < LinkedData::Hypermedia::Resource }
      info = {}
      ld_classes.each do |cls|
        next if routes_by_class[cls].nil? || routes_by_class[cls].empty?
        if cls.respond_to?(:attributes)
          attributes = (cls.attributes(:all) + cls.hypermedia_settings[:serialize_methods]).uniq
        else
          attributes = cls.instance_methods(false)
        end
        attributes_info = {}
        attributes.each do |attribute|
          next if cls.hypermedia_settings[:serialize_never].include?(attribute)

          if cls.ancestors.include?(LinkedData::Models::Base)
            model_cls = cls.range(attribute)
            if model_cls
              type = model_cls.type_uri if model_cls.respond_to?("type_uri")
            end

            shows_default = cls.hypermedia_settings[:serialize_default].empty? ? true : cls.hypermedia_settings[:serialize_default].include?(attribute)

            schema = cls.attribute_settings(attribute) rescue nil
            schema ||= {}
            attributes_info[attribute] = {
              type: type || "",
              shows_default: shows_default || "&nbsp;",
              unique: cls.unique?(attribute) || "&nbsp;",
              required: cls.required?(attribute) || "&nbsp;",
              list: cls.list?(attribute) || "&nbsp;",
              cardinality: cls.cardinality(attribute) || "&nbsp;"
            }
          else
            attributes_info[attribute] = {
              type: "",
              shows_default: "&nbsp;",
              unique: "&nbsp;",
              required: "&nbsp;",
              list: "&nbsp;",
              cardinality: "&nbsp;"
            }
          end
        end

        cls_info = {
          attributes: attributes_info,
          uri: cls.type_uri,
          cls: cls
        }

        info[cls] = cls_info
      end

      # Sort by 'shown by default'
      info.each do |cls, cls_props|
        shown = {}
        not_shown = {}
        cls_props[:attributes].each {|attr,values| values[:shows_default] ? shown[attr] = values : not_shown[attr] = values}
        cls_props[:attributes] = shown.merge(not_shown)
      end

      @metadata_all_info = info
      info
    end

    def hypermedia_links(cls)
      cls.hypermedia_settings[:link_to]
    end

    def routes_by_class
      return @routes_by_class if @routes_by_class
      all_routes = Sinatra::Application.routes
      routes_by_file = {}
      all_routes.each do |method, routes|
        routes.each do |route|
          routes_by_file[route.file] ||= []
          routes_by_file[route.file] << route
        end
      end
      routes_by_class = {}
      routes_by_file.each do |file, routes|
        cls_name = file.split("/").last.gsub(".rb", "").classify.gsub("Controller", "").singularize
        cls = LinkedData::Models.const_get(cls_name) rescue nil

        # Check sub-modules for classes (IE LinkedData::Models::Notes for LinkedData::Models::Notes::Reply)
        if cls.nil?
          LinkedData::Models.constants.each do |const|
            sub_cls = LinkedData::Models.const_get(const).const_get(cls_name) rescue nil
            cls = sub_cls unless sub_cls.nil?
          end
        end

        # Check the map of NON-ONE-TO-ONE mappings
        if cls.nil?
          if CLASS_MAP.include?(cls_name.to_sym)
            cls = CLASS_MAP[cls_name.to_sym].constantize
          end
        end

        next if cls.nil?

        routes.each do |route|
          next if route.verb == "HEAD"
          routes_by_class[cls] ||= []
          routes_by_class[cls] << [route.verb, route.path]
        end
      end
      @routes_by_class = routes_by_class
      routes_by_class
    end

    def route_to_class_map
      return @route_to_class_map if @route_to_class_map
      map = {}
      routes_by_class.each do |cls, routes|
        routes.each do |route|
          map[route[1]] = cls
        end
      end
      @route_to_class_map = map
      map
    end

    def routes_list
      return @navigable_routes if @navigable_routes
      routes = Sinatra::Application.routes["GET"]
      navigable_routes = []
      Sinatra::Application.each_route do |route|
        if route.verb.eql?("GET")
          navigable_routes << route.path.split("?").first
        end
      end
      @navigable_routes = navigable_routes
      navigable_routes
    end

  end
end

