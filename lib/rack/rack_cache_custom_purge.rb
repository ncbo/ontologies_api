require 'net/http'
require 'uri'

module Rack
  module Cache
    class CustomPurge
      def initialize(app = nil)
        @app = app
      end

      def call(env)
        cache_invalidation_methods = ["POST", "PUT", "PATCH", "DELETE"]
        if cache_invalidation_methods.include?(env["REQUEST_METHOD"]) && !env["rack.request.form_hash"].key?("purging_cache")
          path = env["REQUEST_PATH"]
          path_split = path.split("/")
          path_split.each_with_index do |path_part, index|
            next if path_part.empty? || index == path_split.length - 1
            Thread.new {
              uri = URI("#{env["rack.url_scheme"]}://#{env['HTTP_HOST']}#{path_split[0..index].join("/")}")
              Net::HTTP.post_form(uri, {purging_cache: true})
            }
          end
        end
        @app.call(env)
      end

    end
  end
end