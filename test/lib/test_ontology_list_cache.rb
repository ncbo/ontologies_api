require_relative '../test_case'

# Process-level TTL cache for the full ontology list (issue #244).
# Logic tests swap the loader/clock singletons (repo convention, see
# test_search_helper.rb); the final test exercises the real loader
# against the test backend.
class TestOntologyListCache < TestCase

  def setup
    OntologyListCache.invalidate!
  end

  def teardown
    OntologyListCache.invalidate!
  end

  # Fetch the method defined on the class's own singleton, skipping any
  # modules prepended above it (the New Relic tracer wraps traced methods
  # via prepend; capturing the wrapper and later re-defining it as the
  # base method would leave its `super` dangling).
  def own_singleton_method(target, name)
    m = target.method(name)
    m = m.super_method while m && m.owner != target.singleton_class
    refute_nil m, "#{target}.#{name} has no definition on its own singleton"
    m
  end

  # Swap OntologyListCache.load_ontologies for the duration of the block,
  # yielding a counter of loader invocations. Restores the original
  # definition (and its private visibility) afterward.
  def with_loader(result_for_call)
    calls = 0
    original = own_singleton_method(OntologyListCache, :load_ontologies)
    OntologyListCache.define_singleton_method(:load_ontologies) do
      calls += 1
      result_for_call.call(calls)
    end
    yield -> { calls }
  ensure
    OntologyListCache.define_singleton_method(:load_ontologies, original)
    OntologyListCache.singleton_class.send(:private, :load_ontologies)
  end

  def with_clock(time)
    original = own_singleton_method(OntologyListCache, :clock_now)
    OntologyListCache.define_singleton_method(:clock_now) { time }
    yield
  ensure
    OntologyListCache.define_singleton_method(:clock_now, original)
    OntologyListCache.singleton_class.send(:private, :clock_now)
  end

  def test_caches_loaded_list_across_calls
    with_settings(LinkedData::OntologiesAPI.settings, ontology_list_cache_ttl: 300) do
      with_loader(->(_n) { [:a, :b, :c] }) do |calls|
        assert_equal [:a, :b, :c], OntologyListCache.all
        assert_equal [:a, :b, :c], OntologyListCache.all
        assert_equal 1, calls.call, 'loader should run once for two reads inside the TTL'
      end
    end
  end

  def test_returns_isolated_copies
    with_settings(LinkedData::OntologiesAPI.settings, ontology_list_cache_ttl: 300) do
      with_loader(->(_n) { [:a, :b, :c] }) do |_calls|
        first = OntologyListCache.all
        first.select! { |o| o == :a }   # destructive caller, as in get_term_search_query
        first.clear
        assert_equal [:a, :b, :c], OntologyListCache.all,
                     'mutating a returned array must not poison the cache'
      end
    end
  end

  def test_reloads_after_ttl_expires
    with_settings(LinkedData::OntologiesAPI.settings, ontology_list_cache_ttl: 300) do
      with_loader(->(n) { [n] }) do |calls|
        start = Time.now
        with_clock(start)       { assert_equal [1], OntologyListCache.all }
        with_clock(start + 299) { assert_equal [1], OntologyListCache.all }
        with_clock(start + 301) { assert_equal [2], OntologyListCache.all }
        assert_equal 2, calls.call
      end
    end
  end

  def test_ttl_zero_disables_caching
    with_settings(LinkedData::OntologiesAPI.settings, ontology_list_cache_ttl: 0) do
      with_loader(->(n) { [n] }) do |calls|
        assert_equal [1], OntologyListCache.all
        assert_equal [2], OntologyListCache.all
        assert_equal 2, calls.call, 'ttl 0 must bypass the cache entirely'
      end
    end
  end

  def test_ttl_defaults_to_300
    assert_equal 300, LinkedData::OntologiesAPI.settings.ontology_list_cache_ttl
  end

  def test_invalidate_forces_reload
    with_settings(LinkedData::OntologiesAPI.settings, ontology_list_cache_ttl: 300) do
      with_loader(->(n) { [n] }) do |calls|
        assert_equal [1], OntologyListCache.all
        OntologyListCache.invalidate!
        assert_equal [2], OntologyListCache.all
        assert_equal 2, calls.call
      end
    end
  end

  def test_load_failures_propagate_and_are_not_cached
    with_settings(LinkedData::OntologiesAPI.settings, ontology_list_cache_ttl: 300) do
      with_loader(->(n) { n == 1 ? raise(StandardError, 'backend down') : [:recovered] }) do |_calls|
        assert_raises(StandardError) { OntologyListCache.all }
        assert_equal [:recovered], OntologyListCache.all,
                     'a failed load must not leave a poisoned cache entry'
      end
    end
  end

  def test_real_loader_returns_ontologies_with_needed_attributes
    count, _acronyms, _onts = LinkedData::SampleData::Ontology.create_ontologies_and_submissions(
      ont_count: 2, submission_count: 0)
    assert_operator count, :>=, 2

    onts = OntologyListCache.all
    assert_operator onts.length, :>=, 2
    ont = onts.first
    assert_kind_of LinkedData::Models::Ontology, ont

    # Attributes needed by all downstream consumers must be preloaded:
    # acronym (Solr filter), access-control attrs (filter_access),
    # viewOf (site-wide view filtering in Ruby).
    [:acronym, :viewingRestriction, :administeredBy, :acl, :viewOf].each do |attr|
      refute ont.bring?(attr), "#{attr} must be preloaded on cached ontology objects"
    end
  end
end
