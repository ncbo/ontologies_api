require_relative '../test_case_helpers'

class TestSearchHelper < TestCaseHelpers

  # Regression coverage for issue #221: an annotator request with many class
  # hits produced an `fq` with one Solr boolean clause per class id, exceeding
  # Solr's default `maxBooleanClauses` (1024) and returning a 400
  # "too many boolean clauses". The fix routes class_id filters through the
  # Solr `terms` query parser, which collapses to a single non-boolean clause.

  def test_get_terms_field_query_param_uses_solr_terms_parser
    ids = ["http://x.org/A", "http://x.org/B", "http://x.org/C"]
    query = helper.get_terms_field_query_param(ids, "resource_id")

    assert_match(/\A_query_:"\{!terms f=resource_id\}/, query,
                 "expected Solr terms-parser syntax")
    assert_includes query, ids.join(","),
                    "expected ids to be comma-joined as terms-parser values"
    refute_match(/\bOR\b/, query,
                 "must not emit boolean OR-clauses (issue #221)")
  end

  def test_get_terms_field_query_param_returns_empty_for_empty_or_nil_input
    assert_equal "", helper.get_terms_field_query_param([], "resource_id")
    assert_equal "", helper.get_terms_field_query_param(nil, "resource_id")
  end

  # Regression for issue #222. `LinkedData::Models::Class.read_only(doc)` returns
  # a Struct whose fields are exactly `doc.keys`, so a Solr doc with no
  # `prefLabel*` field produced a Struct that did not respond to `prefLabel=`,
  # and `populate_classes_from_search` raised NoMethodError trying to assign
  # `instance.prefLabel = ...`. The fix seeds `doc[:prefLabel]` before
  # `read_only`, guaranteeing the Struct exposes a `prefLabel` accessor.
  def test_populate_classes_from_search_handles_doc_without_preflabel
    fake_ont = Struct.new(:id).new("http://example.org/onto/TEST")
    fake_sub = Struct.new(:ontology).new(fake_ont)
    fake_cls = Struct.new(:id, :submission)
    cls = fake_cls.new("http://example.org/class_1", fake_sub)

    # Solr doc with no prefLabel-bearing field of any kind.
    doc = {
      "resource_id" => "http://example.org/class_1",
      "ontologyId" => "http://example.org/onto/TEST/submissions/1",
      "submissionAcronym" => "TEST",
      "notation" => "test:Class1",
      "obsolete" => false
    }

    h = helper

    h.define_singleton_method(:get_term_search_query) do |_text, params|
      params["fq"] = "*:*"
      ""
    end
    # Sidestep the Sinatra request plumbing that downstream helpers depend on
    # (`params`, `include_param_contains?`, `pref_label_by_language`) -- none
    # of those are what's under test here.
    h.define_singleton_method(:params) { {} }
    h.define_singleton_method(:pref_label_by_language) { |_d| nil }

    klass = LinkedData::Models::Class
    original_search = klass.method(:submit_search_query)
    klass.define_singleton_method(:submit_search_query) do |_query, _params|
      { "response" => { "docs" => [doc] } }
    end

    result = nil
    begin
      result = h.populate_classes_from_search([cls], ["TEST"])
    ensure
      klass.define_singleton_method(:submit_search_query, original_search)
      h.singleton_class.send(:remove_method, :get_term_search_query)
      h.singleton_class.send(:remove_method, :params)
      h.singleton_class.send(:remove_method, :pref_label_by_language)
    end

    refute_nil result, "expected populate_classes_from_search to return a hash"
    assert_equal 1, result.size, "expected exactly one populated class"
    instance = result.values.first
    assert_respond_to instance, :prefLabel,
                      "the read_only Struct must expose a prefLabel accessor (issue #222)"
    assert_nil instance.prefLabel,
               "prefLabel should be nil when the Solr doc has no prefLabel field"
  end

  def test_populate_classes_from_search_uses_terms_parser_for_class_id_fq
    fake_ont = Struct.new(:id).new("http://example.org/onto/TEST")
    fake_sub = Struct.new(:ontology).new(fake_ont)
    fake_cls = Struct.new(:id, :submission)
    classes = (1..3).map { |i| fake_cls.new("http://example.org/class_#{i}", fake_sub) }

    h = helper
    captured = nil

    # Bypass `get_term_search_query` (would otherwise hit the triplestore via
    # `restricted_ontologies`). Seed `fq` with the Solr match-all literal --
    # `populate_classes_from_search` then appends ` AND <class-id-filter>` to it.
    h.define_singleton_method(:get_term_search_query) do |_text, params|
      params["fq"] = "*:*"
      ""
    end

    # Capture the params built by `populate_classes_from_search` instead of
    # actually hitting Solr.
    klass = LinkedData::Models::Class
    original_search = klass.method(:submit_search_query)
    klass.define_singleton_method(:submit_search_query) do |_query, params|
      captured = params.dup
      { "response" => { "docs" => [] } }
    end

    begin
      h.populate_classes_from_search(classes, ["TEST"])
    ensure
      klass.define_singleton_method(:submit_search_query, original_search)
      h.singleton_class.send(:remove_method, :get_term_search_query)
    end

    refute_nil captured, "expected submit_search_query to be invoked"
    assert_match(/\{!terms f=resource_id\}/, captured["fq"],
                 "fq must use the Solr terms parser to avoid 'too many boolean clauses' (issue #221)")
    refute captured["fq"].include?(" OR "),
           "fq must not contain boolean OR-clauses for class_ids (issue #221)"
    classes.each do |c|
      assert_includes captured["fq"], c.id,
                      "fq must include each class id in the terms-parser values"
    end
  end
end
