# frozen_string_literal: true

limit_req_ip = LinkedData::OntologiesAPI.settings.req_per_second_per_ip
limit_req_ip_heavy = limit_req_ip / 5
puts "(API) >> Throttling enabled at #{limit_req_ip} req/sec"

require 'rack/attack'
require 'redis-activesupport'
use Rack::Attack

attack_redis_host_port = {
  host: LinkedData::OntologiesAPI.settings.http_redis_host,
  port: LinkedData::OntologiesAPI.settings.http_redis_port
}
attack_store = ActiveSupport::Cache::RedisStore.new(attack_redis_host_port)
Rack::Attack.cache.store = attack_store

safe_ips = LinkedData::OntologiesAPI.settings.safe_ips ||= Set.new
safe_ips.each do |safe_ip|
  Rack::Attack.safelist_ip(safe_ip)
end

safe_accounts = LinkedData::OntologiesAPI.settings.safe_accounts ||= Set.new(%w[ncbobioportal ontoportal_ui
                                                                                biomixer])
Rack::Attack.safelist('mark safe accounts such as ontoportal_ui and biomixer as safe') do |request|
  request.env['REMOTE_USER'] && safe_accounts.include?(request.env['REMOTE_USER'].username)
end

Rack::Attack.safelist('mark administrators as safe') do |request|
  request.env['REMOTE_USER']&.admin?
end

Rack::Attack.throttle('req/ip/heavy', limit: limit_req_ip_heavy, period: 1.second) do |req|
  req.ip if req.path.include?('/recommender') || req.path.include?('/annotator')
end

Rack::Attack.throttle('req/ip', limit: limit_req_ip, period: 1.second) do |req|
  req.ip
end

Rack::Attack.throttled_responder = lambda do |request|
  match_data = request.env['rack.attack.match_data']

  headers = {
    'RateLimit-Limit' => match_data[:limit].to_s,
    'RateLimit-Remaining' => '0',
    'RateLimit-Reset' => match_data[:period].to_s
  }

  body = "You have made #{match_data[:count]} requests in the last #{match_data[:period]} seconds.
          For user #{request.env['REMOTE_USER']}, we limit API Keys to #{match_data[:limit]} requests every #{match_data[:period]} seconds\n"

  [429, headers, [body]]
end
