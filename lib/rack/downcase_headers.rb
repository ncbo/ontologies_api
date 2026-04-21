module Rack
  class DowncaseHeaders
    def initialize(app)
      @app = app
    end

    def call(env)
      status, headers, body = @app.call(env)
      downcased_headers = headers.each_with_object({}) do |(key, value), new_headers|
        new_headers[key.downcase] = value
      end
      [status, downcased_headers, body]
    end
  end
end