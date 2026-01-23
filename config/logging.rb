require 'logger'

configure do
  log_file = File.new("log/#{settings.environment}.log", 'a+')
  log_file.sync = true
  LOGGER = Logger.new(log_file)
  LOGGER.level = settings.development? ? Logger::DEBUG : Logger::INFO
  set :logger, LOGGER
end
