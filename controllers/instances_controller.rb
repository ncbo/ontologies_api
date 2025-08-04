class InstancesController < ApplicationController

  # Display individuals for a class
  get '/ontologies/:ontology/classes/:cls/instances' do

    ont, sub = get_ontology_and_submission
    check_last_modified_segment(LinkedData::Models::Instance, [ont.acronym])
    cls = get_class(sub)
    error 404 if cls.nil?
    filter_by_label = label_regex_filter
    attributes, page, size, order_by, bring_unmapped_needed  =  settings_params(LinkedData::Models::Instance)



    page_data = LinkedData::Models::Instance.where(filter_classes_by(cls.id))
                                            .in(sub)
                                            .include(attributes)

    page_data.filter(filter_by_label) unless filter_by_label.nil?
    page_data.order_by(order_by) unless order_by.nil?
    page_data = page_data.page(page,size).all

    bring_unmapped_to page_data , sub, LinkedData::Models::Instance if bring_unmapped_needed

    reply page_data
  end

  namespace "/ontologies/:ontology/instances" do
    # Display individuals for an ontology
    get do
      ont, sub = get_ontology_and_submission
      check_last_modified_segment(LinkedData::Models::Instance, [ont.acronym])
      filter_by_label = label_regex_filter
      attributes, page, size, order_by, bring_unmapped_needed  =  settings_params(LinkedData::Models::Instance)


      page_data = LinkedData::Models::Instance.where
                                              .in(sub)
                                              .include(attributes)

      page_data.filter(filter_by_label) unless filter_by_label.nil?
      page_data.order_by(order_by) unless order_by.nil?
      page_data = page_data.page(page,size).all

      bring_unmapped_to page_data , sub, LinkedData::Models::Instance if bring_unmapped_needed

      reply page_data
    end

    get '/:inst' do
      ont, sub = get_ontology_and_submission
      check_last_modified_segment(LinkedData::Models::Instance, [ont.acronym])

      attributes, page, size, order_by, bring_unmapped_needed  =  settings_params(LinkedData::Models::Instance)

      page_data = LinkedData::Models::Instance.find(@params["inst"]).include(attributes).in(sub).first

      bring_unmapped_to [page_data] , sub, LinkedData::Models::Instance if bring_unmapped_needed

      reply page_data
    end
  end


end

