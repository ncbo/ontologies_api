module Rack
  # Canonicalizes URLs by stripping a trailing slash and redirecting to the
  # slash-less form (e.g. `GET /ontologies/` -> 301 `/ontologies`).
  #
  # Implemented as Rack middleware so the redirect happens before Sinatra
  # routing and before any namespace `before` filters run -- routes therefore
  # only ever see canonical paths, and no per-route trailing-slash handling is
  # needed.
  class TrailingSlashRedirect
    def initialize(app)
      @app = app
    end

    def call(env)
      path = env['PATH_INFO']
      return @app.call(env) unless path && path.length > 1 && path.end_with?('/')

      req = Rack::Request.new(env)
      # PATH_INFO keeps percent-encoding (e.g. %2F in class IRIs), so building
      # the location from it round-trips encoded segments unchanged.
      location = +"#{external_scheme(env, req)}://#{req.host_with_port}#{path.chomp('/')}"
      query = env['QUERY_STRING']
      location << "?#{query}" unless query.nil? || query.empty?

      # 301 may turn POST -> GET and drop the body; 308 preserves method + body.
      status = %w[GET HEAD].include?(env['REQUEST_METHOD']) ? 301 : 308
      # A HEAD response must not carry a body.
      body = env['REQUEST_METHOD'] == 'HEAD' ? [] : ['Moved Permanently']
      # The Location's scheme depends on X-Forwarded-Proto, but an outer
      # Rack::Cache keys entries on path+query only. Without no-store it could
      # serve a cached `Location: https://...` to a plain-http client (or vice
      # versa). Keep the scheme-dependent redirect out of the shared cache.
      headers = {
        'location' => location,
        'content-type' => 'text/plain',
        'cache-control' => 'no-store'
      }
      [status, headers, body]
    end

    private

    # Rack 3 no longer trusts X-Forwarded-Proto on `request.scheme`, so a
    # TLS-terminating proxy that forwards to the app over HTTP would otherwise
    # cause us to emit `Location: http://...` for an https:// request. Use the
    # leftmost forwarded value (RFC 7239 chained proxies), else fall back.
    def external_scheme(env, req)
      forwarded = env['HTTP_X_FORWARDED_PROTO'].to_s.split(',').first.to_s.strip.downcase
      %w[http https].include?(forwarded) ? forwarded : req.scheme
    end
  end
end
