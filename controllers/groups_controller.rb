class GroupsController < ApplicationController

  ##
  # Ontology groups
  get "/ontologies/:acronym/groups" do
    check_last_modified_collection(LinkedData::Models::Group)
    ont = Ontology.find(params["acronym"]).include(group: Group.goo_attrs_to_load(includes_param)).first
    error 404, "You must provide a valid `acronym` to retrieve an ontology" if ont.nil?
    reply ont.group
  end

  namespace "/groups" do
    # Display all groups
    get do
      check_last_modified_collection(LinkedData::Models::Group)
      groups = Group.where.include(Group.goo_attrs_to_load(includes_param)).to_a
      reply groups
    end

    # Display a single group
    get '/:acronym' do
      check_last_modified_collection(LinkedData::Models::Group)
      acronym = params["acronym"]
      g = Group.find(acronym).include(Group.goo_attrs_to_load(includes_param)).first
      error 404, "Group #{acronym} not found" if g.nil?
      reply 200, g
    end

    post do
      create_group
    end

    # Create a group with the given acronym
    put '/:acronym' do
      create_group
    end

    # Update an existing submission of an group
    patch '/:acronym' do
      acronym = params["acronym"]
      group = Group.find(acronym).include(Group.attributes).first

      if group.nil?
        error 400, "Group does not exist, please create using HTTP PUT before modifying"
      else
        populate_from_params(group, params)

        if group.valid?
          group.save
        else
          error 400, group.errors
        end
      end
      halt 204
    end

    # Delete a group
    delete '/:acronym' do
      group = Group.find(params["acronym"]).first
      group.delete
      halt 204
    end

    private

    def create_group
      admin_only!
      params ||= @params
      acronym = params["acronym"]
      group = Group.find(acronym).first

      if group.nil?
        group = instance_from_params(Group, params)
      else
        error 400, "Group exists, please use HTTP PATCH to update"
      end

      if group.valid?
        group.save
      else
        error 400, group.errors
      end
      reply 201, group
    end
  end
end
