class CollectionsController < ApplicationController

  namespace "/ontologies/:ontology/collections" do
    get  do
      submission, attributes, bring_unmapped_needed = collections_setting_params
      attributes = attributes.delete_if {|x| x.is_a?(Hash)} # remove :member
      page_data = LinkedData::Models::SKOS::Collection.where
                                                  .in(submission)
                                                  .include(attributes)


      page_data = page_data.all
      if bring_unmapped_needed
        LinkedData::Models::SKOS::Collection.in(submission).models(page_data).include(:unmapped).all
      end

      reply page_data
    end
    namespace "/:collection" do
      get  do
        submission, attributes, bring_unmapped_needed = collections_setting_params
        collection_uri = get_collection_uri(params)

        data = LinkedData::Models::SKOS::Collection.find(collection_uri).in(submission).include(attributes).first
        if data && bring_unmapped_needed
          LinkedData::Models::SKOS::Collection.in(submission).models([data]).include(:unmapped).all
        end
        reply data
      end

      get '/members' do
        ont, submission = get_ontology_and_submission
        attributes, page, size, filter_by_label, order_by, bring_unmapped_needed  =  settings_params(LinkedData::Models::Class)
        collection_uri = get_collection_uri(params)
        data = LinkedData::Models::Class.where(memberOf: collection_uri).in(submission).include(attributes).page(page,size).all
        reply data
      end
    end
  end


end

