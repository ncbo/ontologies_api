
class UsersController < ApplicationController
  namespace "/users" do
    post "/authenticate" do

      # Modify params to show all user attributes
      params["display"] = User.attributes.join(",")

      if params["access_token"]
        user = oauth_authenticate(params)
        user.bring(*User.goo_attrs_to_load(includes_param))
      else
        user = login_password_authenticate(params)
      end
      unless user.nil?
        user.update_last_login
        user.show_apikey = true
        update_current_user(user)
      end
      reply user
    end

    ##
    # This endpoint will create a token and store it on the use-
    # An email is generated with this token, which allows the user
    # to click and login to the UI. The token can then be provided to
    # the /reset_password endpoint to actually reset the password.
    post "/create_reset_password_token" do
      email    = params["email"]
      username = params["username"]
      user = send_reset_token(email, username)

      if user.valid?
        halt 204
      else
        error 422, user.errors
      end
    end

    ##
    # Passing an email, username, and token to this endpoint will
    # authenticate the user and provide back a full user object which
    # can be used to log a user in. This will allow them to change their
    # password and update the user object.
    post "/reset_password" do
      email             = params["email"] || ""
      username          = params["username"] || ""
      token             = params["token"] || ""

      params["display"] = User.attributes.join(",") # used to serialize everything via the serializer

      user, token_accepted = reset_password(email, username, token)
      if token_accepted
        reply user
      else
        error 401, "Password reset not authorized with this token"
      end
    end

    # Display users
    get do
      check_last_modified_collection(User)
      reply get_users
    end

    # Display a single user
    get '/:username' do
      user = User.find(params[:username]).first
      error 404, "Cannot find user with username `#{params['username']}`" if user.nil?
      check_last_modified(user)
      user.bring(*User.goo_attrs_to_load(includes_param))
      reply user
    end

    # Display a single user
    get '/:username/ontologies' do
      user = User.find(params[:username]).first
      error 404, "Cannot find user with username `#{params['username']}`" if user.nil?
      check_last_modified(user)
      reply user.createdOntologies
    end

    # Create user
    post do
      create_user
    end

    # Users get created via put because clients can assign an id (POST is only used where servers assign ids)
    put '/:username' do
      create_user
    end

    # Update an existing submission of an user
    patch '/:username' do
      user = User.find(params[:username]).include(User.attributes).first
      params.delete("role") unless current_user.admin?
      populate_from_params(user, params)
      if user.valid?
        user.save
      else
        error 422, user.errors
      end
      halt 204
    end

    # Delete a user
    delete '/:username' do
      error 403, "Access denied" unless current_user.admin?
      User.find(params[:username]).first.delete
      halt 204
    end

    private


    def create_user(send_notifications: true)
      params ||= @params
      user = User.find(params["username"]).first
      error 409, "User with username `#{params["username"]}` already exists" unless user.nil?
      params.delete("role") unless current_user.admin?
      user = instance_from_params(User, params)
      if user.valid?
        user.save(send_notifications: send_notifications)
      else
        error 422, user.errors
      end
      reply 201, user
    end
  end
end
