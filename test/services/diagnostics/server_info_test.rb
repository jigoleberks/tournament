# test/services/diagnostics/server_info_test.rb
require "test_helper"

module Diagnostics
  class ServerInfoTest < ActiveSupport::TestCase
    test "returns the expected keys with sane values" do
      info = ServerInfo.call

      assert_equal ::AppVersion.current, info[:app_build]
      assert_equal RUBY_VERSION, info[:ruby_version]
      assert_equal ::Rails.version, info[:rails_version]
      assert_equal ::Rails.env, info[:rails_env]
      assert_match(/\A\d+\./, info[:puma_version])      # e.g. "8.0.2"
      assert info[:postgres_version].present?
    end
  end
end
