require_relative '../test_case'

class TestSubmissionMetadataController < TestCase
  ##
  # Test the main submission_metadata endpoint
  def test_submission_metadata_all
    get '/submission_metadata'
    assert last_response.ok?
    assert_equal 200, last_response.status

    metadata = MultiJson.load(last_response.body)
    assert metadata.is_a?(Array)

    # Check that we have metadata for all attributes (or more, in case we add new ones)
    expected_attribute_count = LinkedData::Models::OntologySubmission.attributes(:all).length
    assert metadata.length >= expected_attribute_count,
           "Expected at least #{expected_attribute_count} metadata items, got #{metadata.length}"

    # Check that each metadata item has the expected structure
    metadata.each do |item|
      assert item.key?('@id')
      assert item.key?('@type')
      assert item.key?('attribute')
      assert item.key?('namespace')
      assert item.key?('label')
      assert item.key?('extracted')
      assert item.key?('metadataMappings')
      assert item.key?('enforce')
      assert item.key?('enforcedValues')
      assert item.key?('category')
      assert item.key?('@context')

      # Optional fields that may be present
      # assert item.key?('helpText')  # Optional
      # assert item.key?('description')  # Optional
      # assert item.key?('example')  # Optional
    end
  end

  ##
  # Test the main ontology_metadata endpoint
  def test_ontology_metadata_all
    get '/ontology_metadata'
    assert last_response.ok?
    assert_equal 200, last_response.status

    metadata = MultiJson.load(last_response.body)
    assert metadata.is_a?(Array)

    # Check that we have metadata for all attributes (or more, in case we add new ones)
    expected_attribute_count = LinkedData::Models::Ontology.attributes(:all).length
    assert metadata.length >= expected_attribute_count,
           "Expected at least #{expected_attribute_count} metadata items, got #{metadata.length}"

    # Check that each metadata item has the expected structure
    metadata.each do |item|
      assert item.key?('@id')
      assert item.key?('@type')
      assert item.key?('attribute')
      assert item.key?('namespace')
      assert item.key?('label')
      assert item.key?('extracted')
      assert item.key?('metadataMappings')
      assert item.key?('enforce')
      assert item.key?('enforcedValues')
      assert item.key?('category')
      assert item.key?('@context')

      # Optional fields that may be present
      # assert item.key?('helpText')  # Optional
      # assert item.key?('description')  # Optional
      # assert item.key?('example')  # Optional
    end
  end

  ##
  # Test individual submission metadata attribute endpoint with valid attribute
  def test_submission_metadata_single_valid
    # First get all metadata to find a valid attribute
    get '/submission_metadata'
    assert last_response.ok?
    all_metadata = MultiJson.load(last_response.body)

    # Use the first attribute for testing
    valid_attribute = all_metadata.first['attribute']

    get "/submission_metadata/#{valid_attribute}"
    assert last_response.ok?
    assert_equal 200, last_response.status

    metadata = MultiJson.load(last_response.body)
    assert metadata.is_a?(Hash)
    assert_equal valid_attribute, metadata['attribute']
    assert metadata.key?('@id')
    assert metadata.key?('@type')
    assert metadata.key?('namespace')
    assert metadata.key?('label')
    assert metadata.key?('extracted')
    assert metadata.key?('metadataMappings')
    assert metadata.key?('enforce')
    assert metadata.key?('enforcedValues')
    assert metadata.key?('category')
    assert metadata.key?('@context')
  end

  ##
  # Test individual ontology metadata attribute endpoint with valid attribute
  def test_ontology_metadata_single_valid
    # First get all metadata to find a valid attribute
    get '/ontology_metadata'
    assert last_response.ok?
    all_metadata = MultiJson.load(last_response.body)

    # Use the first attribute for testing
    valid_attribute = all_metadata.first['attribute']

    get "/ontology_metadata/#{valid_attribute}"
    assert last_response.ok?
    assert_equal 200, last_response.status

    metadata = MultiJson.load(last_response.body)
    assert metadata.is_a?(Hash)
    assert_equal valid_attribute, metadata['attribute']
    assert metadata.key?('@id')
    assert metadata.key?('@type')
    assert metadata.key?('namespace')
    assert metadata.key?('label')
    assert metadata.key?('extracted')
    assert metadata.key?('metadataMappings')
    assert metadata.key?('enforce')
    assert metadata.key?('enforcedValues')
    assert metadata.key?('category')
    assert metadata.key?('@context')
  end

  ##
  # Test individual submission metadata attribute endpoint with invalid attribute
  def test_submission_metadata_single_invalid
    invalid_attribute = 'nonexistent_attribute_12345'

    get "/submission_metadata/#{invalid_attribute}"
    assert_equal 404, last_response.status

    error_response = MultiJson.load(last_response.body)
    assert error_response.is_a?(String)
    assert error_response.include?("Metadata for attribute '#{invalid_attribute}' not found")
  end

  ##
  # Test individual ontology metadata attribute endpoint with invalid attribute
  def test_ontology_metadata_single_invalid
    invalid_attribute = 'nonexistent_attribute_12345'

    get "/ontology_metadata/#{invalid_attribute}"
    assert_equal 404, last_response.status

    error_response = MultiJson.load(last_response.body)
    assert error_response.is_a?(String)
    assert error_response.include?("Metadata for attribute '#{invalid_attribute}' not found")
  end

  ##
  # Test that individual metadata matches the corresponding item in the full metadata list
  def test_submission_metadata_consistency
    get '/submission_metadata'
    assert last_response.ok?
    all_metadata = MultiJson.load(last_response.body)

    # Test a few attributes to ensure consistency
    test_attributes = all_metadata.first(3).map { |item| item['attribute'] }

    test_attributes.each do |attribute|
      get "/submission_metadata/#{attribute}"
      assert last_response.ok?
      single_metadata = MultiJson.load(last_response.body)

      # Find the corresponding item in the full list
      full_item = all_metadata.find { |item| item['attribute'] == attribute }

      # Compare the metadata
      assert_equal full_item['@id'], single_metadata['@id']
      assert_equal full_item['@type'], single_metadata['@type']
      assert_equal full_item['attribute'], single_metadata['attribute']
    end
  end

  ##
  # Test that individual ontology metadata matches the corresponding item in the full metadata list
  def test_ontology_metadata_consistency
    get '/ontology_metadata'
    assert last_response.ok?
    all_metadata = MultiJson.load(last_response.body)

    # Test a few attributes to ensure consistency
    test_attributes = all_metadata.first(3).map { |item| item['attribute'] }

    test_attributes.each do |attribute|
      get "/ontology_metadata/#{attribute}"
      assert last_response.ok?
      single_metadata = MultiJson.load(last_response.body)

      # Find the corresponding item in the full list
      full_item = all_metadata.find { |item| item['attribute'] == attribute }

      # Compare the metadata
      assert_equal full_item['@id'], single_metadata['@id']
      assert_equal full_item['@type'], single_metadata['@type']
      assert_equal full_item['attribute'], single_metadata['attribute']
    end
  end

  ##
  # Test URL structure and ID generation
  def test_metadata_url_structure
    get '/submission_metadata'
    assert last_response.ok?
    all_metadata = MultiJson.load(last_response.body)

    # Check that @id URLs follow the expected pattern
    all_metadata.each do |item|
      assert item['@id'].start_with?('http://data.bioontology.org/submission_metadata/')
      assert item['@type'].start_with?('http://data.bioontology.org/metadata/SubmissionMetadata')
    end
  end

  ##
  # Test ontology metadata URL structure
  def test_ontology_metadata_url_structure
    get '/ontology_metadata'
    assert last_response.ok?
    all_metadata = MultiJson.load(last_response.body)

    # Check that @id URLs follow the expected pattern
    all_metadata.each do |item|
      assert item['@id'].start_with?('http://data.bioontology.org/ontology_metadata/')
      assert item['@type'].start_with?('http://data.bioontology.org/metadata/OntologyMetadata')
    end
  end

  ##
  # Test that metadata includes all expected fields
  def test_metadata_completeness
    get '/submission_metadata'
    assert last_response.ok?
    all_metadata = MultiJson.load(last_response.body)

    # Check that each metadata item has all expected fields
    all_metadata.each do |item|
      expected_fields = ['@id', '@type', 'attribute', 'namespace', 'label', 'extracted',
                         'metadataMappings', 'enforce', 'enforcedValues', 'category', '@context']

      expected_fields.each do |field|
        assert item.key?(field), "Missing field: #{field}"
      end
    end
  end

  ##
  # Test that ontology metadata includes all expected fields
  def test_ontology_metadata_completeness
    get '/ontology_metadata'
    assert last_response.ok?
    all_metadata = MultiJson.load(last_response.body)

    # Check that each metadata item has all expected fields
    all_metadata.each do |item|
      expected_fields = ['@id', '@type', 'attribute', 'namespace', 'label', 'extracted',
                         'metadataMappings', 'enforce', 'enforcedValues', 'category', '@context']

      expected_fields.each do |field|
        assert item.key?(field), "Missing field: #{field}"
      end
    end
  end
end
