require "ontologies_linked_data"

# The classes defined here are simple wrappers around objects that exist in other namespaces
# Wrapping them here allows access to them without using the full namespace.
# If additional functionality is needed for ontologies_api only, the class should be moved to its own model file.

Category = LinkedData::Models::Category

Group = LinkedData::Models::Group

Ontology = LinkedData::Models::Ontology

OntologySubmission = LinkedData::Models::OntologySubmission

SubmissionStatus = LinkedData::Models::SubmissionStatus

OntologyFormat = LinkedData::Models::OntologyFormat

Project = LinkedData::Models::Project

Review = LinkedData::Models::Review

User = LinkedData::Models::User

UserRole = LinkedData::Models::Users::Role

ProvisionalClass = LinkedData::Models::ProvisionalClass

ProvisionalRelation = LinkedData::Models::ProvisionalRelation

SearchHelper = Sinatra::Helpers::SearchHelper

Resource = LinkedData::Models::Resource
