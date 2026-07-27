#!/usr/bin/env ruby
# Before/after latency benchmark for the ontology list cache (issue #244,
# PR #245). Alternates identical requests between two running API
# instances so environmental drift (shared staging backends, cache
# warming) affects both revisions equally.
#
# Usage:
#   ruby script/benchmark_search_latency.rb BEFORE_URL AFTER_URL [N]
#
# Example (before = merge-base worktree on 9394, after = branch on 9393):
#   ruby script/benchmark_search_latency.rb http://localhost:9394 http://localhost:9393 30
#
# Prints median/p95/mean per scenario per revision and verifies both
# revisions return identical (port-normalized) response bodies.
require 'net/http'
require 'uri'
require 'json'

before_url, after_url = ARGV[0], ARGV[1]
n = (ARGV[2] || 30).to_i
abort "Usage: #{$0} BEFORE_URL AFTER_URL [N]" unless before_url && after_url

WARMUPS = 5

SCENARIOS = {
  'site-wide search'   => '/search?q=melanoma',
  'scoped search'      => '/search?q=melanoma&ontologies=NCIT,SNOMEDCT,MESH',
  'search incl. views' => '/search?q=cancer&also_include_views=true'
}.freeze

def get(base, path)
  uri = URI.parse(base + path)
  start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
  res = Net::HTTP.get_response(uri)
  elapsed = (Process.clock_gettime(Process::CLOCK_MONOTONIC) - start) * 1000
  raise "#{uri} returned #{res.code}" unless res.code == '200'
  [elapsed, res.body]
end

def stats(times)
  sorted = times.sort
  {
    median: sorted[sorted.length / 2],
    p95: sorted[(sorted.length * 0.95).floor.clamp(0, sorted.length - 1)],
    mean: times.sum / times.length
  }
end

# Hypermedia links embed LinkedData.settings.rest_url_prefix (a fixed
# host:port from the shared config), not the serving port, so normalize
# every localhost:<port> occurrence on both sides before comparing.
def normalize(body, _base)
  body.gsub(/localhost:\d+/, 'HOST')
end

puts "#{WARMUPS} warmups + #{n} alternating measured requests per revision per scenario"
puts "before: #{before_url}   after: #{after_url}\n\n"

SCENARIOS.each do |name, path|
  WARMUPS.times { get(before_url, path); get(after_url, path) }

  before_times, after_times = [], []
  before_body = after_body = nil
  n.times do
    t, before_body = get(before_url, path)
    before_times << t
    t, after_body = get(after_url, path)
    after_times << t
  end

  parity = normalize(before_body, before_url) == normalize(after_body, after_url)
  b, a = stats(before_times), stats(after_times)
  delta = ->(k) { format('%+.1f%%', (a[k] - b[k]) / b[k] * 100) }

  puts "== #{name} (#{path})"
  puts format('   median: %8.1f ms -> %8.1f ms  (%s)', b[:median], a[:median], delta.call(:median))
  puts format('   p95:    %8.1f ms -> %8.1f ms  (%s)', b[:p95], a[:p95], delta.call(:p95))
  puts format('   mean:   %8.1f ms -> %8.1f ms  (%s)', b[:mean], a[:mean], delta.call(:mean))
  puts "   response parity: #{parity ? 'IDENTICAL' : 'DIFFERENT (INVESTIGATE!)'}"
  puts
end
