require 'sinatra/base'

module Sinatra
  module Helpers
    module HTTPCacheHelper
      REDIS = Redis.new(host: LinkedData::OntologiesAPI.settings.http_redis_host,
                        port: LinkedData::OntologiesAPI.settings.http_redis_port)
      @@redis_available = nil

      ##
      # Wrap the exires Sinatra method so we set additional headers appropriately
      def expires(amount, *values)
        return unless cache_enabled?
        cache_headers(amount)
        super(amount, *values)
      end

      ##
      # Check to see if the current object has a last modified, set via sinatra
      def check_last_modified(inst)
        return unless cache_enabled?
        cache_headers(inst.class.max_age)
        last_modified inst.last_modified || inst.cache_write
      end

      ##
      # Check to see if the current object's segment has a last modified, set via sinatra
      def check_last_modified_segment(cls, segment_prefix)
        return unless cache_enabled?
        cache_headers(cls.max_age)
        cache_segment = cls.cache_segment(segment_prefix)
        last_modified cls.segment_last_modified(cache_segment) || cls.cache_segment_write(cache_segment)
      end

      ##
      # Check to see if the collection has a last modified, set via sinatra
      def check_last_modified_collection(cls)
        return unless cache_enabled?
        cache_headers(cls.max_age)
        last_modified cls.collection_last_modified || cls.cache_collection_write
      end

      private

      def cache_enabled?
        @@redis_available ||= REDIS.ping.eql?("PONG") rescue false # Ping redis to make sure it's available
        return false unless @@redis_available
        return false unless LinkedData.settings.enable_http_cache
        return true
      end

      def cache_headers(max_age = 60)
        headers["Vary"] = "User-Agent, Accept, Accept-Language, Accept-Encoding, Authorization"
        headers["Cache-Control"] = "public, max-age=#{max_age}"
      end
    end
  end
end

helpers Sinatra::Helpers::HTTPCacheHelper
