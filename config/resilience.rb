# Web-layer half of goo's SPARQL circuit breakers (goo de-fork review D1/D2, D15).
#
# goo can shed load when the Redis cache or the triple store is failing, but as a library it can
# only raise: it has no way to produce an HTTP response. It raises
# Goo::SPARQL::Resilience::CircuitOpenError, and translating that into a 503 is this file's job.
# Without the translation an open breaker surfaces as a 500 with a stack trace, which is
# indistinguishable from a real bug and tells a client nothing about retrying.
#
# The breaker itself is off unless OP_SPARQL_CIRCUIT_BREAKER is set in the environment; this file
# is inert until then, so it changes nothing on its own.
#
# Why 503 and not 500: the request failed because a dependency is unavailable, not because the
# request was wrong. 503 is the status clients and load balancers already treat as "retry later",
# and it carries Retry-After.

if defined?(Goo::SPARQL::Resilience)

  # 503 + Retry-After for a request that hit an open breaker.
  #
  # Deliberately NOT cached: Rack::Cache sits in front of this app, and caching a shed response
  # would keep serving the outage after the dependency recovered. `no-store` also stops any
  # intermediary from holding on to it.
  error Goo::SPARQL::Resilience::CircuitOpenError do
    err = env['sinatra.error']
    retry_after = begin
      Goo::SPARQL::Resilience.cool_off
    rescue StandardError
      30
    end

    headers 'Retry-After' => retry_after.to_s, 'Cache-Control' => 'no-store'
    LOGGER.error("503 (circuit open): #{err.message} #{request.request_method} #{request.path}")

    status 503
    body({ errors: ['A backend dependency is unavailable; the request was not attempted. ' \
                    'Retry shortly.'],
           status: 503 }.to_json)
  end

  # Breaker state transitions and dropped cache invalidations. goo only warns to stderr, which
  # nothing watches; a load-bearing dependency tripping is page-worthy, so route both through the
  # app logger and New Relic.
  #
  # Called from goo at the moment of transition, NOT per rejected request, so this is safe to make
  # a real reporting call: an outage produces one notice, not one per request.
  Goo::SPARQL::Resilience.on_state_change = lambda do |circuit, from, to, error|
    detail = error ? " (#{error.class}: #{error.message})" : ''
    message = "SPARQL circuit '#{circuit}' #{from} -> #{to}#{detail}"

    if to.to_s == 'red'
      LOGGER.error("ALERT: #{message} -- shedding load for this dependency")
    else
      LOGGER.info(message)
    end

    if defined?(NewRelic::Agent)
      NewRelic::Agent.record_custom_event('SparqlCircuitStateChange',
                                          circuit: circuit.to_s, from: from.to_s, to: to.to_s,
                                          error: error&.class&.to_s)
    end
  rescue StandardError => e
    # Reporting must never be the thing that breaks a request.
    warn "resilience state-change hook failed: #{e.class}: #{e.message}"
  end

  # A dropped invalidation leaves stale cache entries for that graph until its next successful
  # write, so it is worth counting even though it cannot fail the request that caused it.
  Goo::SPARQL::Resilience.on_invalidation_failure = lambda do |graph_key, error|
    LOGGER.warn("SPARQL cache invalidation dropped for #{graph_key}: #{error.class}")

    if defined?(NewRelic::Agent)
      NewRelic::Agent.increment_metric('Custom/SPARQL/CacheInvalidationDropped')
    end
  rescue StandardError => e
    warn "resilience invalidation hook failed: #{e.class}: #{e.message}"
  end

  puts '(API) >> SPARQL circuit breaker ACTIVE (OP_SPARQL_CIRCUIT_BREAKER)' if Goo::SPARQL::Resilience.enabled?
end
