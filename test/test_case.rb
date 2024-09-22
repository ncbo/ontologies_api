# Start simplecov if this is a coverage task or if it is run in the CI pipeline
if ENV['COVERAGE'] == 'true' || ENV['CI'] == 'true'
  require 'simplecov'
  require 'simplecov-cobertura'
  # https://github.com/codecov/ruby-standard-2
  # Generate HTML and Cobertura reports which can be consumed by codecov uploader
  SimpleCov.formatters = SimpleCov::Formatter::MultiFormatter.new([
    SimpleCov::Formatter::HTMLFormatter,
    SimpleCov::Formatter::CoberturaFormatter
  ])
  SimpleCov.start do
    add_filter '/test/'
    add_filter 'app.rb'
    add_filter 'init.rb'
    add_filter '/config/'
  end
end

ENV['RACK_ENV'] = 'test'

require_relative 'test_log_file'
require_relative '../app'
require 'minitest/unit'
require 'webmock/minitest'
MiniTest::Unit.autorun
WebMock.allow_net_connect!
require 'rack/test'
require 'multi_json'
require 'oj'
require 'json-schema'

MAX_TEST_REDIS_SIZE = 10_000

# Check to make sure you want to run if not pointed at localhost
safe_hosts = Regexp.new(/localhost|-ut|ncbo-dev*|ncbo-unittest*/)
def safe_redis_hosts?(sh)
  return [LinkedData.settings.http_redis_host,
   Annotator.settings.annotator_redis_host,
   LinkedData.settings.goo_redis_host].select { |x|
    x.match(sh)
  }.length == 3
end
unless LinkedData.settings.goo_host.match(safe_hosts) &&
        safe_redis_hosts?(safe_hosts) &&
        LinkedData.settings.search_server_url.match(safe_hosts)
  print "\n\n================================== WARNING ==================================\n"
  print "** TESTS CAN BE DESTRUCTIVE -- YOU ARE POINTING TO A POTENTIAL PRODUCTION/STAGE SERVER **\n"
  print "Servers:\n"
  print "triplestore -- #{LinkedData.settings.goo_host}\n"
  print "search -- #{LinkedData.settings.search_server_url}\n"
  print "redis annotator -- #{Annotator.settings.annotator_redis_host}:#{Annotator.settings.annotator_redis_port}\n"
  print "redis http -- #{LinkedData.settings.http_redis_host}:#{LinkedData.settings.http_redis_port}\n"
  print "redis http -- #{LinkedData.settings.http_redis_host}:#{LinkedData.settings.http_redis_port}\n"
  print "redis goo -- #{LinkedData.settings.goo_redis_host}:#{LinkedData.settings.goo_redis_port}\n"
  print "Type 'y' to continue: "
  $stdout.flush
  confirm = $stdin.gets
  if !(confirm.to_s.strip == 'y')
    abort("Canceling tests...\n\n")
  end
  print "Running tests..."
  $stdout.flush
end

class AppUnit < MiniTest::Unit
  def count_pattern(pattern)
    q = "SELECT (count(DISTINCT ?s) as ?c) WHERE { #{pattern} }"
    rs = Goo.sparql_query_client.query(q)
    rs.each_solution do |sol|
      return sol[:c].object
    end
    return 0
  end

  def backend_4s_delete
    if count_pattern("?s ?p ?o") < 400000
      LinkedData::Models::Ontology.where.include(:acronym).each do |o|
        query = "submissionAcronym:#{o.acronym}"
        LinkedData::Models::Ontology.unindexByQuery(query)
      end
      LinkedData::Models::Ontology.indexCommit()
      Goo.sparql_update_client.update("DELETE {?s ?p ?o } WHERE { ?s ?p ?o }")
      LinkedData::Models::SubmissionStatus.init_enum
      LinkedData::Models::OntologyType.init_enum
      LinkedData::Models::OntologyFormat.init_enum
      LinkedData::Models::Users::Role.init_enum
      LinkedData::Models::Users::NotificationType.init_enum
    else
      raise Exception, "Too many triples in KB, does not seem right to run tests"
    end
  end

  def before_suites
    # code to run before the first test (gets inherited in sub-tests)
  end

  def after_suites
    # code to run after the last test (gets inherited in sub-tests)
  end

  def _run_suites(suites, type)
    begin
      before_suites
      super(suites, type)
    ensure
      after_suites
    end
  end

  def _run_suite(suite, type)
    begin
      backend_4s_delete
      suite.before_suite if suite.respond_to?(:before_suite)
      super(suite, type)
    rescue Exception => e
      puts e.message
      puts e.backtrace.join("\n\t")
      puts "Traced from:"
      raise e
    ensure
      backend_4s_delete
      suite.after_suite if suite.respond_to?(:after_suite)
    end
  end
end

AppUnit.runner = AppUnit.new

# All tests should inherit from this class.
# Use 'rake test' from the command line to run tests.
# See http://www.sinatrarb.com/testing.html for testing information
class TestCase < MiniTest::Unit::TestCase
  include Rack::Test::Methods



  def app
    Sinatra::Application
  end

  ##
  # Creates a set of Ontology and OntologySubmission objects and stores them in the triplestore
  # @param [Hash] options the options to create ontologies with
  # @option options [Fixnum] :ont_count Number of ontologies to create
  # @option options [Fixnum] :submission_count How many submissions each ontology should have (acts as max number when random submission count is used)
  # @option options [TrueClass, FalseClass] :random_submission_count Use a random number of submissions between 1 and :submission_count
  # @option options [TrueClass, FalseClass] :process_submission Parse the test ontology file
  def create_ontologies_and_submissions(options = {})
    if options[:process_submission] && options[:process_options].nil?
      options[:process_options] =  { process_rdf: true, extract_metadata: false, generate_missing_labels: false }
    end
    LinkedData::SampleData::Ontology.create_ontologies_and_submissions(options)
  end

  ##
  # Delete all ontologies and their submissions
  def delete_ontologies_and_submissions
    LinkedData::SampleData::Ontology.delete_ontologies_and_submissions
  end

  # Delete triple store models
  # @param [Array] gooModelArray an array of GOO models
  def delete_goo_models(gooModelArray)
    gooModelArray.each do |m|
      next if m.nil?
      m.delete
    end
  end

  # Validate JSON object against a JSON schema.
  # @note schema is only validated after json data fails to validate.
  # @param [String] jsonData a json string that will be parsed by MultiJson.load
  # @param [String] jsonSchemaString a json schema string that will be parsed by MultiJson.load
  # @param [boolean] list set it true for jsonObj array of items to validate against jsonSchemaString
  def validate_json(jsonData, jsonSchemaString, list=false)
    schemaVer = :draft3
    jsonObj = MultiJson.load(jsonData)
    jsonSchema = MultiJson.load(jsonSchemaString)
    assert(
        JSON::Validator.validate(jsonSchema, jsonObj, :list => list, :version => schemaVer),
        JSON::Validator.fully_validate(jsonSchema, jsonObj, :list => list, :version => schemaVer, :validate_schema => true).to_s
    )
  end

  # Abstract method to get error messages during a test.
  def get_errors(response)
    errors = ''
    if response.respond_to?('errors')
      errors += last_response.errors
    end
    errors += '; ' unless errors.empty?
    begin
      errors += MultiJson.load(last_response.body)['errors'].to_s
    rescue
      # pass
    end
    return errors.strip
  end

  def self.enable_security
    @@old_security_setting = LinkedData.settings.enable_security
    LinkedData.settings.enable_security = true
  end

  def self.reset_security(old_security =  @@old_security_setting)
    LinkedData.settings.enable_security = old_security
  end


  def self.make_admin(user)
    user.bring_remaining
    user.role = [LinkedData::Models::Users::Role.find(LinkedData::Models::Users::Role::ADMIN).first]
    user.save
  end

  def self.reset_to_not_admin(user)
    user.bring_remaining
    user.role = [LinkedData::Models::Users::Role.find(LinkedData::Models::Users::Role::DEFAULT).first]
    user.save
  end

  def unused_port
    max_retries = 5
    retries = 0
    server_port = Random.rand(55000..65535)
    while port_in_use?(server_port)
      retries += 1
      break if retries >= max_retries
      server_port = Random.rand(55000..65535)
    end
    server_port
  end
  private
  def port_in_use?(port)
    server = TCPServer.new(port)
    server.close
    false
  rescue Errno::EADDRINUSE
    true
  end

end
