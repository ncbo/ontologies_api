application = 'ontologies_api'
app_path = "/opt/ontoportal/#{application}"
working_directory "#{app_path}/current/"

# Configure the number of Unicorn worker processes:
# - We set the worker count to 1.2x the number of CPU cores, which balances concurrency
#   with memory use for typical BioPortal loads.
# - BioPortal hosts many large ontologies and handles higher API traffic than a typical appliance,
#   so this multiplier is tuned slightly above 1.0 to improve throughput under moderate to heavy load.
# - Lighter deployments (e.g., single-ontology or low-traffic appliances) may benefit from increasing
#   this multiplier further (e.g., 1.5–2.0x), depending on available RAM and expected concurrency.
# - The `.max(2)` ensures we always start at least 2 workers, even on single-core hosts.
worker_processes [(Etc.nprocessors * 1.2).to_i, 2].max

# Match Nginx's default timeout
timeout 90
preload_app true

# This is a systemd-managed service. The /run/unicorn directory is created
# and managed by systemd's RuntimeDirectory=unicorn directive.
# user 'op-backend', 'opdata'

pid '/run/unicorn/unicorn.pid'

stderr_path '/var/log/ontoportal/ontologies_api/unicorn.stderr.log'
stdout_path '/var/log/ontoportal/ontologies_api/unicorn.stdout.log'

# Listen on a Unix domain socket for fast, local communication with the nginx reverse proxy.
# - This is the standard production setup for BioPortal and OntoPortal appliances.
# - nginx connects to this socket (defined in its upstream config) to proxy HTTP requests to Unicorn.
# - The socket path is located in the systemd-managed runtime directory (/run/unicorn),
#   which is automatically cleaned up on reboot.
listen '/run/unicorn/unicorn.sock', backlog: 512

# Optional TCP listener for development or debugging (e.g., curl access without nginx):
# - Not enabled in production.
# listen 8087, backlog: 256

# Ensure Unicorn picks up the correct Gemfile after a rolling restart:
before_exec do |server|
  ENV['BUNDLE_GEMFILE'] = "#{app_path}/current/Gemfile"
end

before_fork do |server, worker|
  ##
  # When sent a USR2, Unicorn will suffix its pidfile with .oldbin and
  # version of our app). When this new Unicorn is completely loaded
  # it will begin spawning workers. The first worker spawned will check to
  # see if an .oldbin pidfile exists. If so, this means we've just booted up
  # a new Unicorn and need to tell the old one that it can now die. To do so
  # we send it a QUIT.
  #
  # Using this method we get 0 downtime deploys.

  old_pid = "#{server.config[:pid]}.oldbin"

  if File.exist?(old_pid) && server.pid != old_pid
    begin
      sig = (worker.nr + 1) >= server.worker_processes ? :QUIT : :TTOU
      Process.kill(sig, File.read(old_pid).to_i)
    rescue Errno::ENOENT, Errno::ESRCH
      # someone else did our job for us
    end
  end
end

after_fork do |server, worker|
  # Unicorn master loads the app then forks off workers - because of the way
  # Unix forking works, we need to make sure we aren't using any of the parent's
  # sockets, e.g. db connection
  #
  # the following is highly recomended for Rails + "preload_app true"
  # as there's no need for the master process to hold a connection
  defined?(ActiveRecord::Base) and ActiveRecord::Base.connection.disconnect!

  # Redis and Memcached would go here but their connections are established
  # on demand, so the master never opens a socket
end
