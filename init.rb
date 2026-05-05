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

# Add optional trailing slash to routes
Sinatra.register do
  def self.registered(app)
    app.routes.each do |verb, routes|
      routes.each do |route|
        pattern = route[0]
        next if pattern.to_s.end_with?('/')

        http_verb = verb.to_s.downcase
        app.public_send(http_verb, "#{pattern}/") do
          pass unless request.path_info.end_with?('/')
          redirect_path = request.path_info.chomp('/')
          redirect canonical_redirect_url(redirect_path), 301
        end
      end
    end
  end
end

helpers do
  def canonical_redirect_url(path)
    url = +"#{external_request_scheme}://#{request.host_with_port}#{path}"
    url << "?#{request.query_string}" unless request.query_string.empty?
    url
  end

  # Rack 3 no longer trusts X-Forwarded-Proto on `request.scheme`, so a
  # TLS-terminating proxy that forwards to the app over HTTP would otherwise
  # cause us to emit `Location: http://...` for an https:// request.
  def external_request_scheme
    forwarded = request.get_header('HTTP_X_FORWARDED_PROTO').to_s
                       .split(',').first.to_s.strip.downcase
    %w[http https].include?(forwarded) ? forwarded : request.scheme
  end
end
