class SchemesController < ApplicationController

  namespace "/ontologies/:ontology/schemes" do
    get  do
      submission, attributes, bring_unmapped_needed = schemes_setting_params

      page_data = LinkedData::Models::SKOS::Scheme.where
                                                  .in(submission)
                                                  .include(attributes)

      page_data = page_data.all
      if bring_unmapped_needed
        LinkedData::Models::SKOS::Scheme.in(submission).models(page_data).include(:unmapped).all
      end

      reply page_data
    end

    get '/:scheme' do
      submission, attributes, bring_unmapped_needed = schemes_setting_params
      scheme_uri = get_scheme_uri(params)

      data = LinkedData::Models::SKOS::Scheme.find(scheme_uri).in(submission).include(attributes).first
      if data && bring_unmapped_needed
        LinkedData::Models::SKOS::Scheme.in(submission).models([data]).include(:unmapped).all
      end
      reply data
    end
  end


end

