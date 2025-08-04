# conig file for unit tests

# GOO_BACKEND_NAME = ENV.include?("GOO_BACKEND_NAME") ? ENV["GOO_BACKEND_NAME"] : "AG"
# GOO_HOST         = ENV.include?("GOO_HOST")         ? ENV["GOO_HOST"]         : "localhost"
# GOO_PATH_QUERY   = ENV.include?("GOO_PATH_QUERY")   ? ENV["GOO_PATH_QUERY"]   : "/repositories/bioportal"
# GOO_PATH_DATA    = ENV.include?("GOO_PATH_DATA")    ? ENV["GOO_PATH_DATA"]    : "/repositories/bioportal/statements"
# GOO_PATH_UPDATE  = ENV.include?("GOO_PATH_UPDATE")  ? ENV["GOO_PATH_UPDATE"]  : "/repositories/bioportal/statements"
# GOO_PORT         = ENV.include?("GOO_PORT")         ? ENV["GOO_PORT"]         : 10035

GOO_BACKEND_NAME = ENV.include?("GOO_BACKEND_NAME") ? ENV["GOO_BACKEND_NAME"] : "4store"
GOO_HOST         = ENV.include?("GOO_HOST")         ? ENV["GOO_HOST"]         : "localhost"
GOO_PATH_DATA    = ENV.include?("GOO_PATH_DATA")    ? ENV["GOO_PATH_DATA"]    : "/data/"
GOO_PATH_QUERY   = ENV.include?("GOO_PATH_QUERY")   ? ENV["GOO_PATH_QUERY"]   : "/sparql/"
GOO_PATH_UPDATE  = ENV.include?("GOO_PATH_UPDATE")  ? ENV["GOO_PATH_UPDATE"]  : "/update/"
GOO_PORT         = ENV.include?("GOO_PORT")         ? ENV["GOO_PORT"]         : 8080

MGREP_DICTIONARY_FILE = ENV.include?("MGREP_DICTIONARY_FILE") ? ENV["MGREP_DICTIONARY_FILE"] : "./test/data/dictionary.txt"
MGREP_HOST       = ENV.include?("MGREP_HOST")       ? ENV["MGREP_HOST"]       : "localhost"


# MGREP_PORT       = ENV.include?("MGREP_PORT")       ? ENV["MGREP_PORT"]       : 55556
MGREP_PORT       = ENV.include?("MGREP_PORT")       ? ENV["MGREP_PORT"]       : 55555


REDIS_GOO_CACHE_HOST  = ENV.include?("REDIS_GOO_CACHE_HOST")  ? ENV["REDIS_GOO_CACHE_HOST"]  : "localhost"
REDIS_HTTP_CACHE_HOST = ENV.include?("REDIS_HTTP_CACHE_HOST") ? ENV["REDIS_HTTP_CACHE_HOST"] : "localhost"
REDIS_PERSISTENT_HOST = ENV.include?("REDIS_PERSISTENT_HOST") ? ENV["REDIS_PERSISTENT_HOST"] : "localhost"
REDIS_PORT            = ENV.include?("REDIS_PORT")            ? ENV["REDIS_PORT"]            : 6379
REPORT_PATH           = ENV.include?("REPORT_PATH")           ? ENV["REPORT_PATH"]           : "./test/ontologies_report.json"
REPOSITORY_FOLDER     = ENV.include?("REPOSITORY_FOLDER")     ? ENV["REPOSITORY_FOLDER"]     : "./test/data/ontology_files/repo"
SOLR_PROP_SEARCH_URL  = ENV.include?("SOLR_PROP_SEARCH_URL")  ? ENV["SOLR_PROP_SEARCH_URL"]  : "http://localhost:8983/solr/prop_search_core1"
SOLR_TERM_SEARCH_URL  = ENV.include?("SOLR_TERM_SEARCH_URL")  ? ENV["SOLR_TERM_SEARCH_URL"]  : "http://localhost:8983/solr/term_search_core1"

LinkedData.config do |config|
  config.goo_backend_name              = GOO_BACKEND_NAME.to_s
  config.goo_host                      = GOO_HOST.to_s
  config.goo_port                      = GOO_PORT.to_i
  config.goo_path_query                = GOO_PATH_QUERY.to_s
  config.goo_path_data                 = GOO_PATH_DATA.to_s
  config.goo_path_update               = GOO_PATH_UPDATE.to_s
  config.goo_redis_host                = REDIS_GOO_CACHE_HOST.to_s
  config.goo_redis_port                = REDIS_PORT.to_i
  config.http_redis_host               = REDIS_HTTP_CACHE_HOST.to_s
  config.http_redis_port               = REDIS_PORT.to_i
  config.search_server_url             = SOLR_TERM_SEARCH_URL.to_s
  config.property_search_server_url    = SOLR_PROP_SEARCH_URL.to_s
  #config.enable_notifications          = false

  # Ontology analytics
  config.ontology_analytics_redis_host  = REDIS_PERSISTENT_HOST.to_s
  config.ontology_analytics_redis_port  = REDIS_PORT.to_i
  config.ontology_analytics_redis_field = 'test_analytics'
end

Annotator.config do |config|
  config.annotator_redis_host  = REDIS_PERSISTENT_HOST.to_s
  config.annotator_redis_port  = REDIS_PORT.to_i
  config.mgrep_host            = MGREP_HOST.to_s
  config.mgrep_port            = MGREP_PORT.to_i
  config.mgrep_dictionary_file = MGREP_DICTIONARY_FILE.to_s
end

LinkedData::OntologiesAPI.config do |config|
  config.http_redis_host = REDIS_HTTP_CACHE_HOST.to_s
  config.http_redis_port = REDIS_PORT.to_i
end

NcboCron.config do |config|
  config.redis_host = REDIS_PERSISTENT_HOST.to_s
  config.redis_port = REDIS_PORT.to_i
#  config.ontology_report_path = REPORT_PATH
end
