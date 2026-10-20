class CategoriesController < ApplicationController

  ##
  # Ontology categories
  get "/ontologies/:acronym/categories" do
    check_last_modified_collection(LinkedData::Models::Category)
    ont = Ontology.find(params["acronym"]).include(hasDomain: Category.goo_attrs_to_load).first
    error 404, "You must provide a valid `acronym` to retrieve an ontology" if ont.nil?
    reply ont.hasDomain
  end

  namespace "/categories" do
    # Display all categories
    get do
      check_last_modified_collection(LinkedData::Models::Category)
      categories = Category.where.include(Category.goo_attrs_to_load(includes_param)).to_a
      reply categories
    end

    # Display a single category
    get '/:acronym' do
      check_last_modified_collection(LinkedData::Models::Category)
      acronym = params["acronym"]
      category = Category.find(acronym).include(Category.goo_attrs_to_load(includes_param)).first
      error 404, "Category #{acronym} not found" if category.nil?
      reply 200, category
    end

    # Create a category with the given acronym
    post do
      create_category
    end

    # Create a category with the given acronym
    put '/:acronym' do
      create_category
    end

    # Update an existing submission of a category
    patch '/:acronym' do
      acronym = params["acronym"]
      category = Category.find(acronym).include(Category.attributes).first

      if category.nil?
        error 400, "Category does not exist, please create using HTTP PUT before modifying"
      else
        populate_from_params(category, params)

        if category.valid?
          category.save
        else
          error 400, category.errors
        end
      end
      halt 204
    end

    # Delete a category
    delete '/:acronym' do
      category = Category.find(params["acronym"]).first
      category.delete
      halt 204
    end

    private

    def create_category
      admin_only!
      params ||= @params
      acronym = params["acronym"]
      category = Category.find(acronym).include(Category.goo_attrs_to_load(includes_param)).first

      if category.nil?
        category = instance_from_params(Category, params)
      else
        error 400, "Category exists, please use HTTP PATCH to update"
      end

      if category.valid?
        category.save
      else
        error 400, category.errors
      end
      reply 201, category
    end
  end
end
