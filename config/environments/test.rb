# conig file for unit tests

GOO_BACKEND_NAME  = ENV.include?("GOO_BACKEND_NAME")  ? ENV["GOO_BACKEND_NAME"]  : "4store"
GOO_HOST          = ENV.include?("GOO_HOST")          ? ENV["GOO_HOST"]          : "localhost"
GOO_PATH_DATA     = ENV.include?("GOO_PATH_DATA")     ? ENV["GOO_PATH_DATA"]     : "/data/"
GOO_PATH_QUERY    = ENV.include?("GOO_PATH_QUERY")    ? ENV["GOO_PATH_QUERY"]    : "/sparql/"
GOO_PATH_UPDATE   = ENV.include?("GOO_PATH_UPDATE")   ? ENV["GOO_PATH_UPDATE"]   : "/update/"
GOO_PORT          = ENV.include?("GOO_PORT")          ? ENV["GOO_PORT"]          : 9000
MGREP_HOST        = ENV.include?("MGREP_HOST")        ? ENV["MGREP_HOST"]        : "localhost"
MGREP_PORT        = ENV.include?("MGREP_PORT")        ? ENV["MGREP_PORT"]        : 55556
REDIS_HOST        = ENV.include?("REDIS_HOST")        ? ENV["REDIS_HOST"]        : "localhost"
REDIS_PORT        = ENV.include?("REDIS_PORT")        ? ENV["REDIS_PORT"]        : 6379
SEARCH_SERVER_URL = ENV.include?('SEARCH_SERVER_URL') ? ENV['SEARCH_SERVER_URL'] : 'http://localhost:8983/solr'

LinkedData.config do |config|
  config.goo_backend_name              = GOO_BACKEND_NAME.to_s
  config.goo_host                      = GOO_HOST.to_s
  config.goo_port                      = GOO_PORT.to_i
  config.goo_path_query                = GOO_PATH_QUERY.to_s
  config.goo_path_data                 = GOO_PATH_DATA.to_s
  config.goo_path_update               = GOO_PATH_UPDATE.to_s
  config.goo_redis_host                = REDIS_HOST.to_s
  config.goo_redis_port                = REDIS_PORT.to_i
  config.http_redis_host               = REDIS_HOST.to_s
  config.http_redis_port               = REDIS_PORT.to_i
  config.search_server_url             = SEARCH_SERVER_URL.to_s
  config.property_search_server_url    = SEARCH_SERVER_URL.to_s

  # Ontology analytics
  config.ontology_analytics_redis_host  = REDIS_HOST.to_s
  config.ontology_analytics_redis_port  = REDIS_PORT.to_i
  config.ontology_analytics_redis_field = 'test_analytics'
  config.oauth_providers = {
    github: {
      check: :access_token,
      link: 'https://api.github.com/user'
    },
    keycloak: {
      check: :jwt_token,
      cert: 'KEYCLOAK_SECRET_KEY'
    },
    orcid: {
      check: :access_token,
      link: 'https://pub.orcid.org/v3.0/me'
    },
    google: {
      check: :access_token,
      link: 'https://www.googleapis.com/oauth2/v3/userinfo'
    }
  }
end

Annotator.config do |config|
  config.annotator_redis_host  = REDIS_HOST.to_s
  config.annotator_redis_port  = REDIS_PORT.to_i
  config.mgrep_host            = MGREP_HOST.to_s
  config.mgrep_port            = MGREP_PORT.to_i
end

LinkedData::OntologiesAPI.config do |config|
  config.http_redis_host = REDIS_HOST.to_s
  config.http_redis_port = REDIS_PORT.to_i
end

NcboCron.config do |config|
  config.redis_host = REDIS_HOST.to_s
  config.redis_port = REDIS_PORT.to_i
end
