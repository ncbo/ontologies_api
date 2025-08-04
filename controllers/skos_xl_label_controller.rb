class SkosXlLabelController < ApplicationController

  namespace "/ontologies/:ontology/skos_xl_labels" do
    get  do
      ont, submission = get_ontology_and_submission
      attributes, page, size, order_by, bring_unmapped_needed  =  settings_params(LinkedData::Models::SKOS::Label)
      labels = LinkedData::Models::SKOS::Label.where.in(submission).include(attributes).page(page, size).all
      if labels && bring_unmapped_needed
        LinkedData::Models::SKOS::Label.in(submission).models(labels).include(:unmapped).all
      end
      reply labels
    end

    get '/:id' do
      ont, submission = get_ontology_and_submission
      attributes, page, size, order_by, bring_unmapped_needed  =  settings_params(LinkedData::Models::SKOS::Label)
      label = LinkedData::Models::SKOS::Label.find(params[:id]).in(submission).include(attributes).first
      if label && bring_unmapped_needed
        LinkedData::Models::SKOS::Label.in(submission).models([label]).include(:unmapped).all
      end
      reply label
    end
  end
end

