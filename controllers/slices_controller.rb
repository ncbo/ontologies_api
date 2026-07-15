class SlicesController < ApplicationController
  namespace "/slices" do
    get do
      expires 3600, :public
      check_last_modified_collection(LinkedData::Models::Slice)
      includes = LinkedData::Models::Slice.goo_attrs_to_load(includes_param)
      reply LinkedData::Models::Slice.where.include(includes).all
    end

    get '/:slice_id' do
      slice = LinkedData::Models::Slice.where(acronym: params["slice_id"]).first
      error 404, "Slice #{params['slice_id']} not found" if slice.nil?
      check_last_modified(slice)
      slice.bring(*LinkedData::Models::Slice.goo_attrs_to_load(includes_param))
      reply slice
    end
    ##
    # Create a new slice
    post do
      admin_only!
      create_slice
    end

    # Delete a slice
    delete '/:slice' do
      admin_only!
      LinkedData::Models::Slice.find(params[:slice]).first.delete
      halt 204
    end

    # Update an existing slice
    patch '/:slice' do
      admin_only!
      slice = LinkedData::Models::Slice.find(params[:slice]).include(LinkedData::Models::Slice.attributes(:all)).first
      populate_from_params(slice, params)
      if slice.valid?
        slice.save
      else
        error 422, slice.errors
      end
      halt 204
    end


    # Check to make sure each group has a corresponding slice (and ontologies match)
    get '/synchronize_groups' do
      admin_only!

      groups = LinkedData::Models::Group.where.include(LinkedData::Models::Group.attributes(:all)).all
      groups.each do |g|
        slice = LinkedData::Models::Slice.find(g.acronym.downcase.gsub(" ", "_")).include(LinkedData::Models::Slice.attributes(:all)).first
        if slice
          slice.ontologies = g.ontologies
          slice.save if slice.valid?
        else
          slice = LinkedData::Models::Slice.new({
                                                  acronym: g.acronym.downcase.gsub(" ", "_"),
                                                  name: g.name,
                                                  description: g.description,
                                                  ontologies: g.ontologies
                                                })
          slice.save rescue reply "Error creating slice: " + slice.errors.to_s
        end
      end
      reply LinkedData::Models::Slice.where.include(LinkedData::Models::Slice.attributes(:all)).all
    end
    
    private

    def create_slice
      params ||= @params
      ontologies = []

      params["ontologies"].each do |ont|
        ontologies.push(LinkedData::Models::Ontology.find(ont).first)
      end

      slice = LinkedData::Models::Slice.new({
                                              acronym: params["acronym"],
                                              name: params["name"],
                                              description: params["description"],
                                              ontologies: ontologies
                                            })

      if slice.valid?
        slice.save
      else
        error 400, slice.errors
      end
      reply 201, slice
    end

  end
end