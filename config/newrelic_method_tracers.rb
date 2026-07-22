# Custom New Relic method tracers for hot request paths.
#
# High-traffic transactions (GET /search, GET .../classes/{cls}/tree)
# spend most of their time in application code that the agent reports as
# a single opaque "Sinatra::Application#GET (unknown)" segment. These
# tracers split that block into named Custom/* child segments so
# transaction traces and the breakdown table show where the time goes.
#
# To instrument another endpoint, add its module/class and methods to the
# registry below; test/helpers/test_newrelic_method_tracers.rb consumes
# the same registry, so new entries are covered automatically.
#
# Must be loaded after init.rb so all traced methods are already defined.
# When the agent is disabled (development/test), the tracers are no-ops.
#
# Kill switch: set NEWRELIC_CUSTOM_TRACERS=off (and restart) to skip
# registration entirely, e.g. to rule instrumentation out while
# debugging. Requires a process restart to take effect either way.
module NewRelicMethodTracers
  # Instance methods, keyed by module/class name. Methods inherited from
  # concerns or mixins (e.g. the tree methods, defined in an
  # ontologies_linked_data concern) can be traced here without touching
  # the defining repo.
  INSTANCE_METHODS = {
    # GET /search pipeline
    'Sinatra::Helpers::SearchHelper' => %i[process_search get_term_search_query
                                           add_matched_fields filter_attrs_by_language],
    # App-wide: ontology access list load + response serialization entry
    'Sinatra::Helpers::ApplicationHelper' => %i[restricted_ontologies reply],
    # GET /ontologies/{ontology}/classes/{cls}/tree pipeline
    'LinkedData::Models::Class' => %i[tree tree_sorted paths_to_root]
  }.freeze

  # Class (singleton) methods, keyed by class name.
  CLASS_METHODS = {
    # Hypermedia links + JSON generation for every API response
    'LinkedData::Serializer' => %i[build_response serialize],
    # Solr query execution incl. Ruby-side response parsing (the HTTP
    # call itself already appears as an External segment)
    'LinkedData::Models::Class' => %i[search]
  }.freeze

  def self.register
    INSTANCE_METHODS.each do |const_name, methods|
      install(Object.const_get(const_name), const_name, methods)
    end

    CLASS_METHODS.each do |const_name, methods|
      install(Object.const_get(const_name).singleton_class, const_name, methods)
    end
  end

  def self.install(target, const_name, methods)
    target.include(::NewRelic::Agent::MethodTracer)

    methods.each do |method_name|
      target.send(:add_method_tracer, method_name, "Custom/#{const_name}/#{method_name}")
    end
  end
end

unless ENV['NEWRELIC_CUSTOM_TRACERS'] == 'off'
  require 'new_relic/agent/method_tracer'
  NewRelicMethodTracers.register
end
