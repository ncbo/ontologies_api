# sinatra-base
require 'sinatra'

# sinatra-contrib
require 'sinatra/respond_with'
require 'sinatra/namespace'

# Other gem dependencies
require 'json'
require 'ontologies_linked_data'

# Logging setup
require_relative "config/logging"

# Development-specific options
if [:development, :console].include?(settings.environment)
  require 'pry' # Debug by placing 'binding.pry' where you want the interactive console to start
end

# Setup the environment
environment = [:production, :development, :test].include?(settings.environment) ? settings.environment : :development
require_relative "config/environments/#{environment}.rb"

# Require middleware
require 'rack/accept'
require 'rack/post-body-to-params'

# Use middleware (ORDER IS IMPORTANT)
use Rack::Accept
use Rack::PostBodyToParams
if [:development].include?(settings.environment)
  require 'rack/perftools_profiler'
  use Rack::PerftoolsProfiler, :default_printer => :pdf, :mode => :cputime, :frequency => 1000
end

# Initialize the app
require_relative 'init'

# Enter console mode
if settings.environment == :console
  require 'rack/test'
  include Rack::Test::Methods; def app() Sinatra::Application end
  Pry.start binding, :quiet => true
  exit
end
