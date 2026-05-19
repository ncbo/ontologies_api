# This is the base class for controllers in the application.
# Code in the before or after blocks will run on every request
class ApplicationController
  include Sinatra::Delegator
  extend Sinatra::Delegator

  # Run before route
  before %r{/ontologies/([^/]+).*} do |acronym|
    if LinkedData.settings.enable_slices && request.get?
      unless ontology_in_slice?(acronym)
        error 404, "Ontology not found"
      end
    end
  end

  # Run after route
  after {
  }

end
