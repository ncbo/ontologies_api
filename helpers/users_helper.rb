require 'sinatra/base'

module Sinatra
  module Helpers
    module UsersHelper
      def get_users
        attributes, page, size, order_by, _ = settings_params(LinkedData::Models::User)
        query = User.where.include(attributes)

        if params['search']
          filter = Goo::Filter.new(:username).regex(params['search'])
          query = query.filter(filter)
        end

        query = query.order_by(order_by || { username: :asc })
        query = query.page(page, size)

        query.all
      end

      def filter_for_user_onts(obj)
        return obj unless obj.is_a?(Enumerable)
        return obj unless env["REMOTE_USER"]
        return obj if env["REMOTE_USER"].customOntology.empty?
        return obj if params["ignore_custom_ontologies"]

        user = env["REMOTE_USER"]

        if obj.first.is_a?(LinkedData::Models::Ontology)
          obj = obj.select {|o| user.custom_ontology_id_set.include?(o.id.to_s)}
        end

        obj
      end

      def send_reset_token(email, username)
        user = LinkedData::Models::User.where(email: email, username: username).include(LinkedData::Models::User.attributes).first
        error 404, "User not found" unless user
        reset_token = token(36)
        user.resetToken = reset_token
        user.resetTokenExpireTime = Time.now.to_i + 1.hours.to_i

        user.save(override_security: true)
        LinkedData::Utils::Notifications.reset_password(user, reset_token)
        user
      end

      def token(len)
        chars = ("a".."z").to_a + ("A".."Z").to_a + ("1".."9").to_a
        token = ""
        1.upto(len) { |i| token << chars[rand(chars.size-1)] }
        token
      end

      def reset_password(email, username, token)
        user = LinkedData::Models::User.where(email: email, username: username).include(User.goo_attrs_to_load(includes_param) + [:resetToken, :passwordHash, :resetTokenExpireTime]).first

        error 404, "User not found" unless user

        user.show_apikey = true
        token_accepted = token.eql?(user.resetToken)
        if token_accepted
          error 401, "Invalid password reset token" if user.resetTokenExpireTime.nil?
          error 401, "The password reset token expired" if user.resetTokenExpireTime < Time.now.to_i
          user.resetToken = nil
          user.resetTokenExpireTime = nil
          user.save(override_security: true) if user.valid?
          user.show_apikey = true
        end

        [user, token_accepted]
      end

      def oauth_authenticate(params)
        access_token  = params["access_token"]
        provider  = params["token_provider"]
        user = LinkedData::Models::User.oauth_authenticate(access_token, provider)
        error 401, "Access token invalid"if user.nil?
        user
      end

      def login_password_authenticate(params)
        user_id       = params["user"]
        user_password = params["password"]
        user = User.find(user_id).include(User.goo_attrs_to_load(includes_param) + [:passwordHash]).first
        authenticated = false
        authenticated = user.authenticate(user_password) unless user.nil?
        error 401, "Username/password combination invalid" unless authenticated

        user
      end
    end
  end
end

helpers Sinatra::Helpers::UsersHelper
