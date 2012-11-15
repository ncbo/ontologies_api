# sinatra-base
require 'sinatra'

# sinatra-contrib
require 'sinatra/respond_with'
require 'sinatra/namespace'

# Other gem dependencies
require 'json'

# Logging setup
require_relative "config/logging"

# Development-specific options
if [:development, :console].include?(settings.environment)
  require 'pry' # Debug by placing 'binding.pry' where you want the interactive console to start
end

# Setup the environment
environment = [:production, :development, :test].include?(settings.environment) ? settings.environment : :development
require_relative "config/environments/#{environment}.rb"

# Initialize the app
require_relative 'init'

# Require middleware
require 'rack/accept'

# Use middleware
use Rack::Accept
use LinkedDataSerializer

# Enter console mode
if settings.environment == :console
  require 'rack/test'
  include Rack::Test::Methods; def app() Sinatra::Application end
  Pry.start binding, :quiet => true
  exit
end