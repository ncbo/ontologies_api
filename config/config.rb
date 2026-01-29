module LinkedData::OntologiesAPI
  extend self
  attr_reader :settings

  @settings = OpenStruct.new
  @settings_run = false

  def config(&block)
    return if @settings_run
    @settings_run = true

    yield @settings if block_given?

    # Set defaults
    @settings.enable_monitoring           ||= false
    @settings.slow_request_log            ||= File.expand_path("../../logs/slow_requests.log", __FILE__)
    @settings.http_redis_host             ||= "localhost"
    @settings.http_redis_port             ||= 6379
    @settings.ontology_rank               ||= {}
    @settings.restrict_download           ||= []
    @settings.enable_miniprofiler         ||= false
    @settings.enable_req_timeout          ||= false
    @settings.req_timeout                 ||= 55
    @settings.enable_throttling           ||= false
    @settings.enable_unicorn_workerkiller ||= false
    @settings.req_per_second_per_ip       ||= 15
    @settings.ontology_report_path        ||= "../ontologies_report.json"

    if @settings.enable_monitoring
      puts "(API) >> Slow queries log enabled: #{@settings.slow_request_log}"
    end
  end

end
