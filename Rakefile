require 'rake/testtask'

task default: %w[test]

Rake::TestTask.new do |t|
  t.libs = []
  t.test_files = FileList['test/**/test*.rb']
end

Rake::TestTask.new do |t|
  t.libs = []
  t.name = "test:controllers"
  t.test_files = FileList['test/controllers/test*.rb']
end

Rake::TestTask.new do |t|
  t.libs = []
  t.name = "test:models"
  t.test_files = FileList['test/models/test*.rb']
end

Rake::TestTask.new do |t|
  t.libs = []
  t.name = "test:helpers"
  t.test_files = FileList['test/helpers/test*.rb']
end

Rake::TestTask.new do |t|
  t.libs = []
  t.name = "test:lib"
  t.test_files = FileList['test/lib/test*.rb']
end

desc "Run test coverage analysis"
task :coverage do
  puts "Code coverage reports will be visible in the /coverage folder"
  ENV["COVERAGE"] = "true"
  Rake::Task["test"].invoke
end

namespace :unicorn do
  namespace :start do
    desc "Unicorn start (production settings)"
    task :production do
      print "Starting unicorn...\n"
      `bundle exec unicorn -p 80 -c config/unicorn.rb -D -E production`
    end

    desc "Unicorn start (development settings)"
    task :development do
      print "Starting unicorn...\n"
      `bundle exec unicorn -p 9393 -c config/unicorn.rb`
    end
  end

  desc "Unicorn stop"
  task :stop do
    `pkill -QUIT -f 'unicorn master'`
    if $?.exitstatus == 1
      puts "Unicorn not running"
    elsif $?.exitstatus == 0
      print "Killing unicorn..."
      pids = `pgrep -f 'unicorn master'`
      while !pids.empty?
        print "."
        pids = `pgrep -f 'unicorn master'`
      end
      print "\n"
    end
  end
end

def clear_cache(env)
  require 'ontologies_linked_data'
  require 'ncbo_annotator'
  require 'ncbo_cron'
  require 'redis'
  require_relative 'config/config'
  require_relative "config/environments/#{env}.rb"
  LinkedData::HTTPCache.invalidate_all
  redis = Redis.new(host: LinkedData.settings.goo_redis_host, port: LinkedData.settings.goo_redis_port, timeout: 30)
  redis.flushdb
  `rm -rf cache/`
end

namespace :cache do
  namespace :clear do
    desc "Clear HTTP cache (production redis and Rack::Cache)"
    task :production do
      clear_cache("production")
    end

    desc "Clear HTTP cache (staging redis and Rack::Cache)"
    task :staging do
      clear_cache("staging")
    end

    desc "Clear HTTP cache (development redis and Rack::Cache)"
    task :development do
      clear_cache("development")
    end
  end
end

namespace :deploy do
  desc "Deploy production"
  task :production do
    puts 'Deploying ontologies_api'
    puts 'Doing pull'
    `git pull`
    puts "Installing bundle"
    `bundle install`
    puts 'Restarting unicorn'
    `sudo env PATH=$PATH rake unicorn:stop`
    `sudo env PATH=$PATH rake unicorn:start:production`
  end
end
