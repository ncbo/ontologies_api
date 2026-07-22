require_relative '../test_case_helpers'

# Guards the custom New Relic instrumentation of the /search request path
# (config/newrelic_method_tracers.rb). If a traced method is renamed or
# moved, add_method_tracer logs a warning and silently no-ops, so without
# these assertions the instrumentation could vanish unnoticed while the
# rest of the suite stays green.
class TestNewRelicMethodTracers < TestCaseHelpers

  TRACED_INSTANCE_METHODS = {
    Sinatra::Helpers::SearchHelper => %i[process_search get_term_search_query
                                         add_matched_fields filter_attrs_by_language],
    Sinatra::Helpers::ApplicationHelper => %i[restricted_ontologies reply]
  }.freeze

  TRACED_CLASS_METHODS = {
    LinkedData::Serializer => %i[build_response serialize],
    LinkedData::Models::Class => %i[search]
  }.freeze

  def test_instance_method_tracers_registered
    TRACED_INSTANCE_METHODS.each do |mod, methods|
      methods.each do |method_name|
        unbound = mod.instance_method(method_name)
        refute_equal mod, unbound.owner,
                     "#{mod}##{method_name} is not wrapped by a method tracer"
        assert_wrapped_by_newrelic(unbound, "#{mod}##{method_name}")
      end
    end
  end

  def test_class_method_tracers_registered
    TRACED_CLASS_METHODS.each do |cls, methods|
      methods.each do |method_name|
        unbound = cls.singleton_class.instance_method(method_name)
        refute_equal cls.singleton_class, unbound.owner,
                     "#{cls}.#{method_name} is not wrapped by a method tracer"
        assert_wrapped_by_newrelic(unbound, "#{cls}.#{method_name}")
      end
    end
  end

  private

  # The tracer wrapper is defined inside the newrelic_rpm gem, so the
  # wrapped method's source_location must point there. This distinguishes
  # a genuine tracer from any other module that happens to prepend.
  def assert_wrapped_by_newrelic(unbound_method, label)
    source_file = unbound_method.source_location&.first.to_s
    assert_match(/newrelic/, source_file,
                 "#{label} is wrapped, but not by newrelic_rpm (source: #{source_file})")
  end
end
