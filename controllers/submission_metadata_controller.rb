class SubmissionMetadataController < ApplicationController
  ##
  # Display all metadata for submissions
  get '/submission_metadata' do
    reply klass_metadata(LinkedData::Models::OntologySubmission, 'submission_metadata')
  end

  ##
  # Display metadata for a specific submission attribute
  get '/submission_metadata/:attribute' do
    attribute = params[:attribute]
    metadata = klass_metadata(LinkedData::Models::OntologySubmission, 'submission_metadata')
    attribute_metadata = metadata.find { |attr| attr[:attribute] == attribute }

    halt 404, "Metadata for attribute '#{attribute}' not found" unless attribute_metadata

    reply attribute_metadata
  end

  ##
  # Display all metadata for ontologies
  get '/ontology_metadata' do
    reply klass_metadata(LinkedData::Models::Ontology, 'ontology_metadata')
  end

  ##
  # Display metadata for a specific ontology attribute
  get '/ontology_metadata/:attribute' do
    attribute = params[:attribute]
    metadata = klass_metadata(LinkedData::Models::Ontology, 'ontology_metadata')
    attribute_metadata = metadata.find { |attr| attr[:attribute] == attribute }

    halt 404, "Metadata for attribute '#{attribute}' not found" unless attribute_metadata

    reply attribute_metadata
  end
end
