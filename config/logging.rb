require 'logger'
require 'rack/common_logger'

class CustomLogger < Logger
  alias write <<

  def flush
    ((instance_variable_get :@logdev).instance_variable_get :@dev).flush
  end
end

if [:development, :console].include?(settings.environment)
  LOGGER = CustomLogger.new(STDOUT)
  LOGGER.level = Logger::DEBUG
else
  Dir.mkdir('log') unless File.exist?('log')
  log = File.new("log/#{settings.environment}.log", 'a+')
  log.sync = true
  LOGGER = CustomLogger.new(log)
  LOGGER.level = Logger::INFO
  use Rack::CommonLogger, log
end

set :logger, LOGGER
