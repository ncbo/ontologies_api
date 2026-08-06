require_relative '../test_case'

# The web-layer half of goo's circuit breakers (goo de-fork review D1/D2/D15): goo raises
# CircuitOpenError when it sheds load, and config/resilience.rb must turn that into a 503 rather
# than letting it surface as a 500. Without this the "fail fast and shed load" design is only half
# implemented, since a 500 tells a client nothing about retrying and reads as an application bug.
#
# The breaker itself is not exercised here (that is goo's test/test_resilience.rb). This asserts
# only the translation, by making a goo query raise the way an open breaker would.
module CircuitOpenInjector
  class << self
    attr_accessor :armed
  end

  def query(*args, **kwargs, &block)
    if CircuitOpenInjector.armed
      raise Goo::SPARQL::Resilience::CircuitOpenError, "circuit 'goo:redis' is open"
    end

    super
  end
end

unless Goo::SPARQL::Client.ancestors.include?(CircuitOpenInjector)
  Goo::SPARQL::Client.prepend(CircuitOpenInjector)
end

class TestResilience503 < TestCase
  def teardown
    CircuitOpenInjector.armed = false
  end

  def test_open_circuit_returns_503_not_500
    CircuitOpenInjector.armed = true
    get '/ontologies'

    assert_equal 503, last_response.status,
                 'an open breaker must shed load as 503, not look like an application bug (500)'
    parsed = MultiJson.load(last_response.body)
    assert_equal 503, parsed['status']
    refute_empty parsed['errors']
  end

  def test_503_tells_the_client_when_to_retry_and_is_not_cacheable
    CircuitOpenInjector.armed = true
    get '/ontologies'

    # Retry-After should reflect the breaker's own cool-off, so clients back off for about as long
    # as the breaker stays open rather than guessing.
    assert_equal Goo::SPARQL::Resilience.cool_off.to_s, last_response.headers['Retry-After']

    # Rack::Cache fronts this app; a cached 503 would keep serving the outage after recovery.
    assert_includes last_response.headers['Cache-Control'].to_s, 'no-store'
  end

  def test_normal_requests_are_unaffected
    CircuitOpenInjector.armed = false
    get '/ontologies'

    assert_equal 200, last_response.status
    refute_equal 'no-store', last_response.headers['Cache-Control'].to_s
  end

  # goo calls these at state transitions and when it drops an invalidation. They are the only
  # signal that a dependency has tripped, so they must be wired and must never raise: an exception
  # here would surface inside whatever request happened to trigger the transition.
  def test_reporting_hooks_are_wired_and_cannot_raise
    assert_respond_to Goo::SPARQL::Resilience.on_state_change, :call,
                      'goo needs a state-change hook or a tripped breaker is invisible'
    assert_respond_to Goo::SPARQL::Resilience.on_invalidation_failure, :call

    Goo::SPARQL::Resilience.on_state_change.call('goo:redis', :green, :red,
                                                 Redis::CannotConnectError.new('down'))
    Goo::SPARQL::Resilience.on_state_change.call('goo:redis', :red, :green, nil)
    Goo::SPARQL::Resilience.on_invalidation_failure.call(
      'sparql:graph:http://example.org/g', Goo::SPARQL::Resilience::CircuitOpenError.new('open')
    )
  end
end
