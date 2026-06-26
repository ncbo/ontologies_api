require_relative '../test_case'

# Verifies the `admin_only!` authorization gate (helpers/application_helper.rb):
# every endpoint guarded by it must return 403 for an authenticated non-admin.
# `admin_only!` is the first line of each guarded handler, so it halts before
# any endpoint work runs -- no valid payload or target resource is required.
#
# The "admin is allowed through" path is left to the existing endpoint tests
# (e.g. test_slices_controller, test_users_controller); it is not re-exercised
# here to avoid their side effects (slice/user mutation, annotator dictionary
# and cache rebuilds).
class TestAdminOnlyEndpoints < TestCase

  # [http verb, path] for every reachable handler that calls `admin_only!`.
  #
  # GET /slices/synchronize_groups also calls admin_only! but is unreachable --
  # the earlier `get '/:slice_id'` route shadows it -- so it is omitted here.
  ADMIN_ONLY_ENDPOINTS = [
    [:post,   "/slices"],
    [:patch,  "/slices/any"],
    [:delete, "/slices/any"],
    [:delete, "/users/any"],
    [:post,   "/annotator/dictionary"],
    [:post,   "/annotator/cache"]
  ].freeze

  def before_suite
    self.class.enable_security
    self.class.delete_user("test-admin-gate")
    @@user = self.class.create_user("test-admin-gate")
  end

  def after_suite
    self.class.delete_user("test-admin-gate")
    self.class.reset_security
  end

  def setup
    self.class.enable_security
    self.class.reset_to_not_admin(@@user)
  end

  def test_admin_only_endpoints_forbidden_for_non_admin
    ADMIN_ONLY_ENDPOINTS.each do |verb, path|
      send(verb, "#{path}?apikey=#{@@user.apikey}")

      assert_equal 403, last_response.status,
                   "expected 403 for #{verb.upcase} #{path} as a non-admin user, " \
                   "got #{last_response.status}: #{last_response.body}"
      assert_match(/access denied/i, last_response.body,
                   "expected an 'Access denied' body for #{verb.upcase} #{path}")
    end
  end
end
