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
          redirect redirect_path, 301
        end
      end
    end
  end
end
