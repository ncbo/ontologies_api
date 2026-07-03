require_relative '../test_case'

# When a goo circuit breaker is open it raises Goo::SPARQL::Resilience::CircuitOpenError; the
# API's base-controller handler must translate that into a 503 (+ Retry-After), not a 500.
# (Breaker resilience itself is opt-in in goo; here we simulate an open breaker by making the
# endpoint's goo call raise, so the test needs no live outage.)
class TestCircuitBreaker < TestCase
  def test_circuit_open_error_maps_to_503
    skip 'resilience-enabled goo not present' unless defined?(Goo::SPARQL::Resilience)

    klass = LinkedData::Models::Ontology
    klass.define_singleton_method(:where) do |*_args|
      raise Goo::SPARQL::Resilience::CircuitOpenError, "circuit 'goo:redis' is open"
    end

    begin
      get '/ontologies'
    ensure
      klass.singleton_class.send(:remove_method, :where) # restore the inherited .where
    end

    assert_equal 503, last_response.status
    assert_equal '30', last_response.headers['Retry-After']
    assert_match(/temporarily unavailable/i, last_response.body)
  end
end
