# frozen_string_literal: true

puts "(API) >> Throttling enabled at #{LinkedData::OntologiesAPI.settings.req_per_second_per_ip} req/sec"

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
Rack::Attack.safelist('mark safe accounts such as ontoportal_ui and biomixer as safe') do |req|
  safe_accounts.include?(req.env['REMOTE_USER']&.username)
end

Rack::Attack.safelist('mark administrators as safe') do |req|
  req.env['REMOTE_USER']&.admin?
end

Rack::Attack.throttle('req/ip', limit: LinkedData::OntologiesAPI.settings.req_per_second_per_ip,
                                period: 1.second, &:ip)

Rack::Attack.throttled_response = lambda do |env|
  match_data = env['rack.attack.match_data']
  headers = {
    'RateLimit-Limit' => match_data[:limit].to_s,
    'RateLimit-Remaining' => '0',
    'RateLimit-Reset' => match_data[:period].to_s
  }
  body = "You have made #{match_data[:count]} requests in the last #{match_data[:period]} seconds. For user #{env['REMOTE_USER']}, we limit API Keys to #{match_data[:limit]} requests every #{match_data[:period]} seconds"
  [429, headers, [body]]
end
