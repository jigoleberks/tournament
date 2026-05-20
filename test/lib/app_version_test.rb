require "test_helper"

class AppVersionTest < ActiveSupport::TestCase
  include ActiveSupport::Testing::TimeHelpers

  setup do
    @original_app_version = ENV["APP_VERSION"]
    # Start each test from a cold process: AppVersion holds module-level memo
    # state and we are specifically testing how it behaves across a deploy.
    AppVersion.instance_variables.each { |ivar| AppVersion.remove_instance_variable(ivar) }
  end

  teardown { ENV["APP_VERSION"] = @original_app_version }

  test "current re-resolves on every call so a post-pull deploy is reflected without restarting Puma" do
    ENV["APP_VERSION"] = "deploy-one"
    AppVersion.current # first resolution, as on the first service-worker request after boot

    # The deploy: APP_VERSION (stand-in for the checked-out git SHA) changes
    # while the Puma process keeps running -- bin/update's `docker compose up -d`
    # is a no-op for the already-running, volume-mounted web container. A
    # process-lifetime memo would keep returning "deploy-one", so the service
    # worker cache key would never bump.
    ENV["APP_VERSION"] = "deploy-two"
    assert_equal "deploy-two", AppVersion.current
  end

  test "boot_fallback stays fixed for the life of the process" do
    # Reached only when there is no APP_VERSION and no .git directory. It must
    # be memoized: recomputing a timestamp per request would churn the service
    # worker cache key on every navigation.
    first = AppVersion.boot_fallback
    travel 1.hour do
      assert_equal first, AppVersion.boot_fallback
    end
  end
end
