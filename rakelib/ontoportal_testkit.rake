begin
  require "ontoportal/testkit/tasks"
rescue LoadError
  # ontoportal_testkit lives in group :test. Deploy/prod bundles built with
  # BUNDLE_WITHOUT=test (and Capistrano prod hosts) don't include it, so the
  # require would fail and Rake would abort before any other task could run.
  # Skip silently — testkit tasks are intentionally unavailable outside dev/test.
end
