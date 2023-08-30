# config valid only for Capistrano 3

APP_PATH = '/srv/ontoportal'

set :application, 'ontologies_api'
set :repo_url, "https://github.com/ncbo/#{fetch(:application)}.git"

set :deploy_via, :remote_cache

# Default branch is :master
# ask :branch, proc { `git rev-parse --abbrev-ref HEAD`.chomp }

# Default deploy_to directory is /var/www/my_app
set :deploy_to, "#{APP_PATH}/#{fetch(:application)}"

# Default value for :scm is :git
# set :scm, :git

# Default value for :format is :pretty
# set :format, :pretty

# Default value for :log_level is :debug
# set :log_level, :debug

# Default value for :pty is false
# set :pty, true

# Default value for :linked_files is []
# set :linked_files, %w{config/database.yml}

# Default value for linked_dirs is []
# set :linked_dirs, %w{log tmp/pids tmp/cache tmp/sockets vendor/bundle public/system}
set :linked_dirs, %w{log vendor/bundle tmp/pids tmp/sockets public/system}

# rbenv
# set :rbenv_type, :system #or :user
# set :rbenv_ruby, '2.2.5'
# set :rbenv_roles, :all # default value

# do not use sudo
set :use_sudo, false
# required for restarting unicorn with sudo
set :pty, true
# Default value for default_env is {}
set :default_env, {
}

# Default value for keep_releases is 5
set :keep_releases, 5

# inspired by http://nathaniel.talbott.ws/blog/2013/03/14/post-deploy-smoke-tests/
desc 'Run smoke test'
task :smoke_test do
  on roles(:app) do
    curl_opts = '--max-time 240 --connect-timeout 15 --retry 2'
    failed_tests = []
    curl_result = `curl #{curl_opts} -s -w "%{http_code}" "#{host}/documentation" -o /dev/null`
    failed_tests << 'Documentation smoke test FAILURE.' unless (curl_result == '200')

    if defined?(APIKEY)
      curl_result = `curl #{curl_opts} -s -w "%{http_code}" "#{host}/ontologies?include=all&include_views=true&apikey=#{APIKEY}" -o /dev/null`
      failed_tests << 'Ontologies smoke test FAILURE.' unless (curl_result == '200')
    end
    if failed_tests.empty?
      puts "smoke test passed on #{host}"
    else
      puts "\n\n****************************\n\n"
      puts "SMOKE TEST FAILED on #{host}\n\n"
      failed_tests.each do |failure|
        puts failure
      end
      puts "\n\n****************************\n\n"
    end
  end
end


namespace :deploy do

  desc 'Incorporate the private repository content'
  # Get cofiguration from repo if PRIVATE_CONFIG_REPO env var is set
  # or get config from local directory if LOCAL_CONFIG_PATH env var is set
  task :get_config do
    if defined?(PRIVATE_CONFIG_REPO)
      TMP_CONFIG_PATH = "/tmp/#{SecureRandom.hex(15)}"
      on roles(:app) do
        execute "git clone -q #{PRIVATE_CONFIG_REPO} #{TMP_CONFIG_PATH}"
        execute "rsync -av #{TMP_CONFIG_PATH}/#{fetch(:application)}/ #{release_path}/"
        execute "rm -rf #{TMP_CONFIG_PATH}"
      end
    elsif defined?(LOCAL_CONFIG_PATH)
      on roles(:app) do
        execute "rsync -av #{LOCAL_CONFIG_PATH}/#{fetch(:application)}/ #{release_path}/"
      end
    end
  end

  desc 'Restart application'
  task :restart do
    on roles(:app), in: :sequence, wait: 5 do
    # Your restart mechanism here, for example:
    # execute :touch, release_path.join('tmp/restart.txt')
    execute 'sudo systemctl restart unicorn'
    execute 'sleep 5'
    end
  end

  after :publishing, :get_config
  after :get_config, :restart
  # after :deploy, :smoke_test
  after "deploy:updated", "newrelic:notice_deployment"

  after :restart, :clear_cache do
    on roles(:web), in: :groups, limit: 3, wait: 10 do
      # Here we can do anything such as:
      # within release_path do
      #   execute :rake, 'cache:clear'
      # end
    end
  end
end
