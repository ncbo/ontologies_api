# Recursively require files from directories
def require_dir(dir)
  Dir.glob("#{dir}/**/*.rb").sort.each { |f| require_relative f }
end

# Require core files
require_relative 'controllers/application_controller'
require_dir('lib')
require_dir('helpers')
require_dir('models')
require_dir('controllers')

# Trailing-slash canonicalization is handled by Rack::TrailingSlashRedirect
# (see app.rb / lib/rack/trailing_slash_redirect.rb).
