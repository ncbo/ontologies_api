require_relative '../test_case_helpers'

# Guards the custom New Relic instrumentation registered by
# config/newrelic_method_tracers.rb. If a traced method is renamed or
# moved, add_method_tracer logs a warning and silently no-ops, so without
# these assertions the instrumentation could vanish unnoticed while the
# rest of the suite stays green.
#
# The tests iterate the registry itself, so entries added to
# NewRelicMethodTracers::INSTANCE_METHODS / CLASS_METHODS are covered
# automatically.
class TestNewRelicMethodTracers < TestCaseHelpers

  def test_instance_method_tracers_registered
    NewRelicMethodTracers::INSTANCE_METHODS.each do |const_name, methods|
      mod = Object.const_get(const_name)
      methods.each do |method_name|
        assert_wrapped_by_newrelic(mod.instance_method(method_name),
                                   "#{const_name}##{method_name}")
      end
    end
  end

  def test_class_method_tracers_registered
    NewRelicMethodTracers::CLASS_METHODS.each do |const_name, methods|
      singleton = Object.const_get(const_name).singleton_class
      methods.each do |method_name|
        assert_wrapped_by_newrelic(singleton.instance_method(method_name),
                                   "#{const_name}.#{method_name}")
      end
    end
  end

  private

  # The tracer wrapper is defined inside the newrelic_rpm gem, so the
  # wrapped method's source_location must point there. This distinguishes
  # a genuine tracer from the untraced original (defined in this repo or
  # its gems) and from any other module that happens to prepend.
  def assert_wrapped_by_newrelic(unbound_method, label)
    source_file = unbound_method.source_location&.first.to_s
    assert_match(/newrelic/, source_file,
                 "#{label} is not wrapped by a newrelic_rpm method tracer (source: #{source_file})")
  end
end
