require_relative '../test_case_helpers'

class TestSlicesHelper < TestCaseHelpers

  def before_suite
    self.backend_4s_delete

    @@orig_slices_setting = LinkedData.settings.enable_slices
    LinkedData.settings.enable_slices = true
    @@onts = LinkedData::SampleData::Ontology.create_ontologies_and_submissions(ont_count: 5, submission_count: 0)[2]
    @@group_acronym = "test-group"
    @@group = self.class._create_group
    @@onts[0..2].each do |o|
      o.bring_remaining
      o.group = [@@group]
      o.save
    end

    @@search_onts = LinkedData::SampleData::Ontology.create_ontologies_and_submissions({
      ont_count: 2,
      submission_count: 1,
      acronym: "PARSED",
      process_submission: true
    })[2]
    @@search_onts.first.bring_remaining
    @@search_onts.first.group = [@@group]
    @@search_onts.first.save

    @@group.bring(:ontologies)

    LinkedData::Models::Slice.synchronize_groups_to_slices
  end

  def after_suite
    LinkedData.settings.enable_slices = @@orig_slices_setting
    self.backend_4s_delete
  end

  def test_filtered_list
    get "http://#{@@group_acronym}.dev/ontologies"
    assert last_response.ok?
    onts = MultiJson.load(last_response.body)
    group_ids = @@group.ontologies.map {|o| o.id.to_s}
    assert_equal onts.map {|o| o["@id"]}.sort, group_ids.sort
  end

  def test_filtered_list_header
    get "/ontologies", {}, "HTTP_NCBO_SLICE" => @@group_acronym
    assert last_response.ok?
    onts = MultiJson.load(last_response.body)
    group_ids = @@group.ontologies.map {|o| o.id.to_s}
    assert_equal onts.map {|o| o["@id"]}.sort, group_ids.sort
  end

  def test_filtered_list_header_override
    get "http://#{@@group_acronym}/ontologies", {}, "HTTP_NCBO_SLICE" => @@group_acronym
    assert last_response.ok?
    onts = MultiJson.load(last_response.body)
    group_ids = @@group.ontologies.map {|o| o.id.to_s}
    assert_equal onts.map {|o| o["@id"]}.sort, group_ids.sort
  end

  def test_search_slices
    # Make sure group and non-group onts are in the search index
    get "/search?q=a*&pagesize=500"
    assert last_response.ok?
    results = MultiJson.load(last_response.body)["collection"]
    ont_ids = Set.new(results.map {|r| r["links"]["ontology"]})
    assert_equal ont_ids.to_a.sort, @@search_onts.map {|o| o.id.to_s}.sort

    # Do a search on the slice
    get "http://#{@@group_acronym}/search?q=a*&pagesize=500"
    assert last_response.ok?
    results = MultiJson.load(last_response.body)["collection"]
    group_ids = @@group.ontologies.map {|o| o.id.to_s}
    assert results.all? {|r| group_ids.include?(r["links"]["ontology"])}
  end

  private

  def self._create_group
    LinkedData::Models::Group.new({
      acronym: @@group_acronym,
      name: "Test Group"
    }).save
  end
end
