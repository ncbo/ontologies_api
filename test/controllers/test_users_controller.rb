require_relative '../test_case'

class TestUsersController < TestCase
  def before_suite
    # Create a bunch of test users
    @@usernames = %w(fred goerge henry ben mark matt charlie)

    # Create them again
    @@users = @@usernames.map do |username|
      User.new(username: username, email: "#{username}@example.org", password: "pass_word").save
    end

    # Test data
    @@username = "test_user"
  end

  def self._delete_users
    @@usernames.each do |username|
      user = User.find(username).first
      user.delete unless user.nil?
    end
  end

  def test_rejects_restricted_user_attributes_on_post_and_patch
    username = "restricted_test_user"
    email = "restricted@example.org"
    password = "testpass"

    # Create baseline user
    post "/users", {
      username: username,
      email: email,
      password: password
    }
    assert_equal 201, last_response.status

    # POST attempt with restricted attributes
    post "/users", {
      username: "new-user",
      email: "new@example.org",
      password: "newpass",
      created: DateTime.now,
      resetToken: "invalid",
      resetTokenExpireTime: DateTime.now
    }
    assert_equal 400, last_response.status
    assert_includes last_response.body, "restricted attributes"

    # PATCH attempt with restricted attributes
    patch "/users/#{username}", {
      created: DateTime.now,
      resetToken: "still-invalid",
      resetTokenExpireTime: DateTime.now
    }
    assert_equal 400, last_response.status
    assert_includes last_response.body, "restricted attributes"
  end

  def test_admin_creation
    existent_user = @@users.first #no admin

    refute _create_admin_user(apikey: existent_user.apikey), "A no admin user can't create an admin user or update it to an admin"

    existent_user = self.class.make_admin(existent_user)
    assert _create_admin_user(apikey: existent_user.apikey), "Admin can create an admin user or update it to be an admin"
    self.class.reset_to_not_admin(existent_user)
    _delete_user(@@username)
  end

  def test_all_users
    get '/users'
    assert last_response.ok?
    users = MultiJson.load(last_response.body)
    assert users.any? {|u| u["username"].eql?("fred")}
    assert users.length >= @@usernames.length

    get '/users?search=fred'
    assert last_response.ok?
    users = MultiJson.load(last_response.body)
    assert users.all? {|u| u["username"].include?("fred")}
    assert users.length == 1

    get '/users?page=1&pagesize=5'
    assert last_response.ok?
    users = MultiJson.load(last_response.body)
    assert_equal 5, users["collection"].length
    assert users["totalCount"] >= @@usernames.length
  end

  def test_single_user
    user = 'fred'
    get "/users/#{user}"
    assert last_response.ok?

    assert_equal "fred", MultiJson.load(last_response.body)["username"]
  end

  def test_hide_sensitive_data
    user = @@users[0]
    reset_token = token(36)
    user.resetToken = reset_token
    user.resetTokenExpireTime = Time.now.to_i - 2.hours.to_i
    user.save

    username = user.username
    get "/users/#{username}?display=resetToken,resetTokenExpireTime"
    assert last_response.ok?

    refute_includes MultiJson.load(last_response.body), 'resetToken', "resetToken should NOT be included in the response"
    refute_includes MultiJson.load(last_response.body), 'resetTokenExpireTime', "resetTokenExpireTime should NOT be included in the response"
  end

  def test_create_new_user
    user = {email: "#{@@username}@example.org", password: "pass_the_word"}
    put "/users/#{@@username}", MultiJson.dump(user), "CONTENT_TYPE" => "application/json"
    assert last_response.status == 201
    created_user = MultiJson.load(last_response.body)
    assert created_user["username"].eql?(@@username)

    get "/users/#{@@username}"
    assert last_response.ok?
    assert MultiJson.load(last_response.body)["username"].eql?(@@username)

    _delete_user(created_user["username"])

    post "/users", MultiJson.dump(user.merge(username: @@username)), "CONTENT_TYPE" => "application/json"
    assert last_response.status == 201
    assert MultiJson.load(last_response.body)["username"].eql?(@@username)

    get "/users/#{@@username}"
    assert last_response.ok?
    assert MultiJson.load(last_response.body)["username"].eql?(@@username) 
    assert_equal "test_user@example.org", MultiJson.load(last_response.body)["email"]
  end

  def test_reset_password
    username = 'resetpswd'
    user = {email: "#{username}@example.org", password: "resetme"}
    put "/users/#{username}", MultiJson.dump(user), "CONTENT_TYPE" => "application/json"
    assert last_response.status == 201
    user = User.find(username).include(User.attributes).first
    assert_nil user.resetToken
    post "/users/create_reset_password_token", {username: username, email: "bademail@example.org"}
    user = User.find(username).include(User.attributes).first
    assert_nil user.resetToken
    assert_equal 404, last_response.status
    post "/users/reset_password", {username: 'badusername', email: "#{username}@example.org", token: 'badtoken'}
    post "/users/create_reset_password_token", {username: username, email: "#{username}@example.org"}
    assert_equal 204, last_response.status
    user = User.find(username).include(User.attributes).first
    refute_nil user.resetToken
    post "/users/reset_password", {username: username, email: "#{username}@example.org", token: 'badtoken'}
    assert_equal 401, last_response.status
    post "/users/reset_password", {username: 'badusername', email: "#{username}@example.org", token: 'badtoken'}
    assert_equal 404, last_response.status
    post "/users/reset_password", {username: username, token: user.resetToken}
    assert_equal 404, last_response.status
    post "/users/reset_password", {email: "#{username}@example.org", token: user.resetToken}
    assert_equal 404, last_response.status
    post "/users/reset_password", {username: username, email: "badexampe@example.org", token: user.resetToken}
    assert_equal 404, last_response.status
    post "/users/reset_password", {username: username, email: "#{username}@example.org", token: user.resetToken}
    assert_equal 200, last_response.status
    assert_equal "#{username}@example.org", MultiJson.load(last_response.body)["email"]
    user = User.find(username).include(User.attributes).first
    assert_nil user.resetToken
  end

  def test_reset_password_expired_token
    username = 'resetexpired'
    user = {email: "#{username}@example.org", password: "resetme"}
    put "/users/#{username}", MultiJson.dump(user), "CONTENT_TYPE" => "application/json"
    assert last_response.status == 201
    post "/users/create_reset_password_token", {username: username, email: "#{username}@example.org"}
    assert_equal 204, last_response.status
    user = User.find(username).include(User.attributes).first
    user.resetTokenExpireTime = Time.now.to_i - 2.hours.to_i
    user.save
    post "/users/reset_password", {username: username, email: "#{username}@example.org", token: user.resetToken}
    assert_equal 401, last_response.status
  end


  def test_create_new_invalid_user
    put "/users/totally_new_user"
    assert last_response.status == 422
  end

  def test_no_duplicate_user
    put "/users/fred"
    assert last_response.status == 409
  end

  def test_update_patch_user
    add_first_name = {firstName: "Fred"}
    patch "/users/fred", MultiJson.dump(add_first_name), "CONTENT_TYPE" => "application/json"
    assert last_response.status == 204

    get "/users/fred?include=all"
    fred = MultiJson.load(last_response.body)
    assert fred["firstName"].eql?("Fred")
  end

  def test_delete_user
    self.class.enable_security

    delete "/users/ben?apikey=#{@@users.first.apikey}"
    assert_equal 403,  last_response.status

    self.class.make_admin(@@users.first)
    delete "/users/ben?apikey=#{@@users.first.apikey}"
    assert_equal 204,  last_response.status

    @@usernames.delete("ben")
    self.class.reset_security
    self.class.reset_to_not_admin(@@users.first)

    get "/users/ben"
    assert_equal 404, last_response.status
  end

  def test_user_not_found
    get "/users/this_user_definitely_does_not_exist"
    assert last_response.status == 404
  end

  def test_authentication
    post "/users/authenticate", {user: @@usernames.first, password: "pass_word"}
    assert last_response.ok?
    user = MultiJson.load(last_response.body)
    assert user["username"].eql?(@@usernames.first)
  end

  private

  def token(len)
    chars = ("a".."z").to_a + ("A".."Z").to_a + ("1".."9").to_a
    token = ""
    1.upto(len) { |i| token << chars[rand(chars.size-1)] }
    token
  end

  def _delete_user(username)
    LinkedData::Models::User.find(@@username).first&.delete
  end
  def _create_admin_user(apikey: nil)
    user = {email: "#{@@username}@example.org", password: "pass_the_word", role: ['ADMINISTRATOR']}
    _delete_user(@@username)

    put "/users/#{@@username}", MultiJson.dump(user), "CONTENT_TYPE" => "application/json", "Authorization" => "apikey token=#{apikey}"
    assert last_response.status == 201
    created_user = MultiJson.load(last_response.body)
    assert created_user["username"].eql?(@@username)

    get "/users/#{@@username}?apikey=#{apikey}"
    assert last_response.ok?
    user = MultiJson.load(last_response.body)
    assert user["username"].eql?(@@username)

    return true if user["role"].eql?(['ADMINISTRATOR'])

    patch "/users/#{@@username}", MultiJson.dump(role: ['ADMINISTRATOR']), "CONTENT_TYPE" => "application/json", "Authorization" => "apikey token=#{apikey}"
    assert last_response.status == 204

    get "/users/#{@@username}?apikey=#{apikey}"
    assert last_response.ok?
    user = MultiJson.load(last_response.body)
    assert user["username"].eql?(@@username)

    true if user["role"].eql?(['ADMINISTRATOR'])
  end
end
