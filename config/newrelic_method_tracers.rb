# Custom New Relic method tracers for the /search request path.
#
# The GET /search transaction spends >90% of its time in application code
# that the agent reports as a single opaque "Sinatra::Application#GET
# (unknown)" segment (~830 ms of the ~890 ms average). These tracers split
# that block into named Custom/* child segments so transaction traces and
# the breakdown table show where the time actually goes.
#
# Must be loaded after init.rb so all traced methods are already defined.
# When the agent is disabled (development/test), the tracers are no-ops.
require 'new_relic/agent/method_tracer'

module Sinatra
  module Helpers
    module SearchHelper
      include ::NewRelic::Agent::MethodTracer

      add_method_tracer :process_search, 'Custom/SearchHelper/process_search'
      add_method_tracer :get_term_search_query, 'Custom/SearchHelper/get_term_search_query'
      add_method_tracer :add_matched_fields, 'Custom/SearchHelper/add_matched_fields'
      # Called once per returned document (default pagesize 50).
      add_method_tracer :filter_attrs_by_language, 'Custom/SearchHelper/filter_attrs_by_language'
    end

    module ApplicationHelper
      include ::NewRelic::Agent::MethodTracer

      # Site-wide searches load every ontology here before querying Solr.
      add_method_tracer :restricted_ontologies, 'Custom/ApplicationHelper/restricted_ontologies'
      add_method_tracer :reply, 'Custom/ApplicationHelper/reply'
    end
  end
end

# Serialization of the result page (hypermedia links + JSON generation).
LinkedData::Serializer.singleton_class.class_eval do
  include ::NewRelic::Agent::MethodTracer

  add_method_tracer :build_response, 'Custom/LinkedData::Serializer/build_response'
  add_method_tracer :serialize, 'Custom/LinkedData::Serializer/serialize'
end

# Solr query execution + response parsing (the HTTP call itself is already
# instrumented as an External segment; this segment adds the parse cost).
LinkedData::Models::Class.singleton_class.class_eval do
  include ::NewRelic::Agent::MethodTracer

  add_method_tracer :search, 'Custom/LinkedData::Models::Class/search'
end
