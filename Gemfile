source 'https://rubygems.org'

gem 'activesupport'
# see https://github.com/ncbo/ontologies_api/issues/69
gem 'bigdecimal'
gem 'json-schema'
gem 'multi_json'
gem 'oj'
gem 'parseconfig'
gem 'rack'
gem 'rake'
gem 'rexml' # Investigate why unicorn fails to start under ruby 3 without adding rexml gem to the Gemfile
gem 'rackup'
gem 'sinatra'

github 'sinatra/sinatra' do
  gem 'sinatra-contrib'
end

gem 'request_store'
gem 'parallel'
gem 'google-protobuf', '3.25.3'
gem 'grpc', '1.70.1'
gem 'net-ftp'
gem 'json-ld', '~> 3.2.0'
gem 'rdf-raptor', github:'ruby-rdf/rdf-raptor', ref: '6392ceabf71c3233b0f7f0172f662bd4a22cd534' # use version 3.3.0 when available

# Rack middleware
gem 'ffi'
gem 'rack-accept'
gem 'rack-attack', require: 'rack/attack'
gem 'rack-cache' # see https://github.com/ncbo/ontologies_api/issues/118
gem 'rack-cors', require: 'rack/cors'
# GitHub dependency can be removed when https://github.com/niko/rack-post-body-to-params/pull/6 is merged and released
gem 'rack-post-body-to-params', github: 'palexander/rack-post-body-to-params', branch: 'multipart_support'
gem 'rack-timeout'
gem 'redis-rack-cache'

# Data access (caching)
gem 'redis'
gem 'redis-store'

# HTTP server
gem 'unicorn'
gem 'unicorn-worker-killer'

# Templating
gem 'haml', '~> 5.2.2' # pin see https://github.com/ncbo/ontologies_api/pull/107
gem 'rack-contrib'
gem 'pandoc-ruby'

# NCBO gems (can be from a local dev path or from rubygems/git)
gem 'goo', github: 'ncbo/goo', branch: 'ontoportal-lirmm-development'
gem 'sparql-client', github: 'ncbo/sparql-client', branch: 'ontoportal-lirmm-development'
gem 'ncbo_annotator', github: 'ncbo/ncbo_annotator', branch: 'chore/ruby3.2-rdf3-compat'
gem 'ncbo_cron', github: 'ncbo/ncbo_cron', branch: 'develop'
gem 'ncbo_ontology_recommender', github: 'ncbo/ncbo_ontology_recommender', branch: 'develop'
gem 'ontologies_linked_data', github: 'ncbo/ontologies_linked_data', branch: 'chore/ontoportal-lirmm-goo-compat'

group :development do
  # bcrypt_pbkdf and ed35519 is required for capistrano deployments when using ed25519 keys; see https://github.com/miloserdow/capistrano-deploy/issues/42
  gem 'shotgun', github: 'palexander/shotgun', branch: 'ncbo'
  gem 'rubocop'
end

group :deployment do
  # bcrypt_pbkdf and ed35519 is required for capistrano deployments when using ed25519 keys; see https://github.com/miloserdow/capistrano-deploy/issues/42
  gem 'bcrypt_pbkdf', '>= 1.0', '< 2.0', require: false
  gem 'capistrano', '~> 3', require: false
  gem 'capistrano-bundler', require: false
  gem 'capistrano-locally', require: false
  gem 'capistrano-rbenv', require: false
  gem 'ed25519', '>= 1.2', '< 2.0', require: false
end

group :profiling do
  gem 'rack-mini-profiler'
end

group :test do
  gem 'byebug', '~> 12.0'
  gem 'crack', '0.4.5'
  gem 'minitest'
  gem 'minitest-hooks'
  gem 'minitest-stub_any_instance'
  gem 'minitest-reporters'
  gem 'rack-test'
  gem 'simplecov', require: false
  gem 'simplecov-cobertura' # for codecov.io
  gem 'webmock'
  gem 'webrick'
end
