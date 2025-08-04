class UsersController < ApplicationController
  namespace "/users" do

    post "/authenticate" do
      user_id       = params["user"]
      user_password = params["password"]
      # Modify params to show all user attributes
      params["display"] = User.attributes.join(",")
      user = User.find(user_id).include(User.goo_attrs_to_load(includes_param) + [:passwordHash]).first
      authenticated = user.authenticate(user_password) unless user.nil?
      error 401, "Username/password combination invalid" unless authenticated
      user.show_apikey = true
      reply user
    end

    ##
    # This endpoint will create a token and store it on the use-
    # An email is generated with this token, which allows the user
    # to click and login to the UI. The token can then be provided to
    # the /reset_password endpoint to actually reset the password.
    post "/create_reset_password_token" do
      email = params["email"]
      username = params["username"]
      user = LinkedData::Models::User.where(email: email, username: username).include(LinkedData::Models::User.attributes).first
      error 404, "User not found" unless user
      reset_token = token(36)
      user.resetToken = reset_token
      user.resetTokenExpireTime = Time.now.to_i + 1.hours.to_i
      if user.valid?
        user.save(override_security: true)
        LinkedData::Utils::Notifications.reset_password(user, reset_token)
      else
        error 422, user.errors
      end
      halt 204
    end

    ##
    # Passing an email, username, and token to this endpoint will
    # authenticate the user and provide back a full user object which
    # can be used to log a user in. This will allow them to change their
    # password and update the user object.
    post "/reset_password" do
      email = params["email"] || ""
      username = params["username"] || ""
      token = params["token"] || ""

      params["display"] = User.attributes.join(",") # used to serialize everything via the serializer
      user = LinkedData::Models::User.where(email: email, username: username).include(User.goo_attrs_to_load(includes_param)).first
      error 404, "User not found" unless user

      user.bring(:resetToken)
      user.bring(:resetTokenExpireTime)
      user.bring(:passwordHash)

      if token.eql?(user.resetToken)
        error 401, "Invalid password reset token" if user.resetTokenExpireTime.nil?
        error 401, "The password reset token expired" if user.resetTokenExpireTime < Time.now.to_i
        user.resetToken = nil
        user.resetTokenExpireTime = nil

        if user.valid?
          user.save(override_security: true)
          user.show_apikey = true
          reply user
        else
          error 422, "Error resetting password"
        end
      else
        error 401, "Password reset not authorized with this token"
      end
    end

    # Display all users
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

    def token(len)
      chars = ("a".."z").to_a + ("A".."Z").to_a + ("1".."9").to_a
      token = ""
      1.upto(len) { |i| token << chars[rand(chars.size-1)] }
      token
    end

    def create_user
      params ||= @params
      user = User.find(params["username"]).first
      error 409, "User with username `#{params["username"]}` already exists" unless user.nil?
      params.delete("role") unless current_user.admin?
      user = instance_from_params(User, params)
      if user.valid?
        user.save
      else
        error 422, user.errors
      end
      reply 201, user
    end
  end
end
