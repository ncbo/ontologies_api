require 'digest'
require 'json'
require 'net/http'
require 'time'
require 'uri'

before_url = URI(ENV.fetch('BEFORE_URL', 'http://localhost:9393/metrics/missing'))
after_url = URI(ENV.fetch('AFTER_URL', 'http://localhost:9394/metrics/missing'))
warmups = Integer(ENV.fetch('WARMUPS', 5))
samples = Integer(ENV.fetch('SAMPLES', 30))
read_timeout = Integer(ENV.fetch('READ_TIMEOUT', 300))

raise 'WARMUPS must not be negative' if warmups.negative?
raise 'SAMPLES must be positive' unless samples.positive?
raise 'READ_TIMEOUT must be positive' unless read_timeout.positive?

def canonicalize(value)
  case value
  when Array
    value.map { |item| canonicalize(item) }
  when Hash
    value.keys.sort.to_h { |key| [key, canonicalize(value.fetch(key))] }
  else
    value
  end
end

def canonical_response(response)
  canonical = canonicalize(response)
  return canonical unless canonical.is_a?(Array)

  canonical.sort_by do |item|
    item.is_a?(Hash) ? item.fetch('acronym', JSON.generate(item)) : JSON.generate(item)
  end
end

def fetch(url, read_timeout:, label:)
  warn "#{Time.now.utc.iso8601} start #{label}"
  request = Net::HTTP::Get.new(url)
  started_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
  response = Net::HTTP.start(url.host, url.port, open_timeout: 10, read_timeout: read_timeout) do |http|
    http.request(request)
  end
  elapsed_ms = (Process.clock_gettime(Process::CLOCK_MONOTONIC) - started_at) * 1_000
  raise "#{url} returned HTTP #{response.code}" unless response.is_a?(Net::HTTPSuccess)

  warn "#{Time.now.utc.iso8601} finish #{label}: #{elapsed_ms.round(1)} ms"
  [elapsed_ms, canonical_response(JSON.parse(response.body))]
end

def percentile(values, percentile)
  sorted = values.sort
  index = [(sorted.length * percentile).ceil - 1, 0].max
  sorted.fetch(index)
end

def median(values)
  sorted = values.sort
  midpoint = sorted.length / 2
  return sorted.fetch(midpoint) if sorted.length.odd?

  (sorted.fetch(midpoint - 1) + sorted.fetch(midpoint)) / 2
end

def summarize(values)
  {
    median_ms: median(values).round(1),
    p95_ms: percentile(values, 0.95).round(1),
    mean_ms: (values.sum / values.length).round(1)
  }
end

def percent_delta(before, after)
  (((after - before) / before) * 100).round(1)
end

expected_response = nil
warmups.times do |index|
  _before_ms, before_response = fetch(before_url, read_timeout: read_timeout,
                                                  label: "warmup #{index + 1}/#{warmups} before")
  _after_ms, after_response = fetch(after_url, read_timeout: read_timeout,
                                               label: "warmup #{index + 1}/#{warmups} after")
  raise 'Before and after warmup responses differ.' unless before_response == after_response
  raise 'The response changed during warmup.' if expected_response && expected_response != before_response

  expected_response ||= before_response
end

timings = { before: [], after: [] }
samples.times do |index|
  before_ms, before_response = fetch(before_url, read_timeout: read_timeout,
                                                 label: "sample #{index + 1}/#{samples} before")
  after_ms, after_response = fetch(after_url, read_timeout: read_timeout,
                                              label: "sample #{index + 1}/#{samples} after")
  raise 'Before and after measured responses differ.' unless before_response == after_response
  raise 'The response changed during measurement.' if expected_response && expected_response != before_response

  expected_response ||= before_response
  timings.fetch(:before) << before_ms
  timings.fetch(:after) << after_ms
end

before_summary = summarize(timings.fetch(:before))
after_summary = summarize(timings.fetch(:after))
canonical_json = JSON.generate(expected_response)

result = {
  compared: {
    before: before_url.to_s,
    after: after_url.to_s
  },
  method: {
    warmups_per_revision: warmups,
    measured_requests_per_revision: samples,
    measured_order: 'alternating before, after',
    read_timeout_seconds: read_timeout
  },
  response: {
    entries: expected_response.length,
    canonical_sha256: Digest::SHA256.hexdigest(canonical_json),
    canonical_bytes: canonical_json.bytesize
  },
  latency: {
    before: before_summary,
    after: after_summary,
    percent_delta: before_summary.to_h do |metric, before_value|
      [metric, percent_delta(before_value, after_summary.fetch(metric))]
    end
  },
  samples_ms: {
    before: timings.fetch(:before).map { |value| value.round(1) },
    after: timings.fetch(:after).map { |value| value.round(1) }
  }
}

puts JSON.pretty_generate(result)
