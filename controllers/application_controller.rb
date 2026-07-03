# This is the base class for controllers in the application.
# Code in the before or after blocks will run on every request
class ApplicationController
  include Sinatra::Delegator
  extend Sinatra::Delegator

  # A goo circuit breaker (Redis cache or SPARQL endpoint) is open: the dependency is failing, so
  # shed load fast with 503 + Retry-After instead of surfacing a 500, and log the trip so it's
  # alertable. Guarded by defined? so the API doesn't hard-depend on a resilience-enabled goo
  # build (the breaker is opt-in via OP_SPARQL_CIRCUIT_BREAKER).
  if defined?(Goo::SPARQL::Resilience)
    error Goo::SPARQL::Resilience::CircuitOpenError do
      halt 503, { 'Retry-After' => '30' },
           { errors: ['A backend dependency is temporarily unavailable; please retry.'],
             status: 503 }
    end

    # Log breaker state transitions once (not per rejected request). Point this at NewRelic /
    # statsd for paging if desired.
    Goo::SPARQL::Resilience.on_state_change ||= lambda do |name, from, to, error|
      level = to.to_s == 'red' ? :error : :info
      detail = error ? " (#{error.class}: #{error.message})" : ''
      LOGGER.public_send(level, "[circuit] #{name} #{from} -> #{to}#{detail}")
    end
  end

  # Run before route
  before %r{/ontologies/([^/]+).*} do |acronym|
    if LinkedData.settings.enable_slices && request.get?
      unless ontology_in_slice?(acronym)
        error 404, "Ontology not found"
      end
    end
  end

  # Run after route
  after {
  }

end
