require_relative '../test_case'

class TestOntologyAnalyticsController < TestCase
  ANALYTICS_DATA = JSON.parse(
    File.read(File.expand_path('../data/ontology_analytics_data.json', __dir__))
  )

  class << self
    attr_accessor :redis, :onts, :user
  end

  def before_suite
    self.class.redis = Redis.new(host: LinkedData.settings.ontology_analytics_redis_host,
                                 port: LinkedData.settings.annotator_analytics_redis_port)
    db_size = self.class.redis.dbsize
    if db_size > MAX_TEST_REDIS_SIZE
      puts(
        "This test cannot be run because there are #{db_size} Redis entries " \
        "(max #{MAX_TEST_REDIS_SIZE}). You are probably pointing to the wrong Redis backend."
      )
      return
    end
    self.class.redis.set(LinkedData.settings.ontology_analytics_redis_field, Marshal.dump(ANALYTICS_DATA))
    self.class.onts = {
      'NCIT' => 'NCIT Ontology', 'ONTOMA' => 'ONTOMA Ontology', 'CMPO' => 'CMPO Ontology', 'AEO' => 'AEO Ontology',
      'SNOMEDCT' => 'SNOMEDCT Ontology', 'TST' => 'TST Ontology'
    }
    self.class._delete
    self.class._create_user
    self.class._create_onts
  end

  def after_all
    self.class.redis&.del(LinkedData.settings.ontology_analytics_redis_field)
    self.class._delete
    super
  end

  def self._create_user
    username = 'tim'
    test_user = LinkedData::Models::User.new(
      username: username,
      email: "#{username}@example.org",
      password: 'password'
    )
    test_user.save if test_user.valid?
    self.user = test_user.valid? ? test_user : LinkedData::Models::User.find(username).first
  end

  def self._create_onts
    onts.each do |acronym, name|
      ont = LinkedData::Models::Ontology.new(
        acronym: acronym,
        name: name,
        administeredBy: [user]
      )
      ont.save
    end
  end

  def self._delete_onts
    onts.each_key do |acronym|
      ont = LinkedData::Models::Ontology.find(acronym).first
      ont&.delete
    end
  end

  def self._delete
    _delete_onts
    test_user = LinkedData::Models::User.find('tim').first
    test_user&.delete
  end

  def test_invalid_query_params
    get '/analytics?year=2014&month=14'
    assert_equal(400, last_response.status, get_errors(last_response))

    get '/analytics?year=20142&month=3'
    assert_equal(400, last_response.status, get_errors(last_response))
  end

  def test_ontology_filtering
    get '/analytics?ontologies=NCIT,ONTOMA'
    assert last_response.ok?
    analytics = MultiJson.load(last_response.body)
    assert_equal 2, analytics.length
  end

  def test_month_filtering
    get '/analytics?ontologies=NCIT,ONTOMA&month=2'
    assert last_response.ok?
    analytics = MultiJson.load(last_response.body)
    analytics.each_key { |k| assert_equal 10, analytics[k].length }
  end

  def test_specific_month_and_year
    get '/analytics?year=2014&month=04'
    assert last_response.ok?
    analytics = MultiJson.load(last_response.body)

    assert_equal 6, analytics.length
    assert_equal 20_376, analytics['SNOMEDCT']['2014']['4']
    assert_equal 1, analytics['SNOMEDCT'].length
    assert_equal 12, analytics['CMPO']['2014']['4']
    analytics.each_value do |v|
      assert_equal 1, v.length
      assert_equal '2014', v.keys[0]
      assert_equal '4', v[v.keys[0]].keys[0]
    end
  end

  def test_analytics_index
    get '/analytics'
    assert last_response.ok?
    analytics = MultiJson.load(last_response.body)
    assert_equal 6, analytics.length
    analytics.each_key { |k| assert_equal 10, analytics[k].length }
  end

  def test_missing_ontology
    get '/ontologies/NON_EXISTENT/analytics'
    assert_equal(404, last_response.status, get_errors(last_response))
  end

  def test_single_ontology
    get '/ontologies/TST/analytics'
    assert last_response.ok?
    analytics = MultiJson.load(last_response.body)
    assert_equal 1, analytics.length
    assert_equal 10, analytics[analytics.keys[0]].length
    assert_equal 2000, analytics['TST']['2015']['1']
  end

  def test_ontology_csv
    get '/ontologies/TST/analytics?format=csv'
    assert last_response.ok?
    headers = last_response.headers
    assert_equal 'text/csv;charset=utf-8', headers['Content-Type']
    assert_equal 'attachment; filename="analytics-TST.csv"', headers['Content-Disposition']
  end
end
