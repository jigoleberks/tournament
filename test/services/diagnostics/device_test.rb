# test/services/diagnostics/device_test.rb
require "test_helper"

module Diagnostics
  class DeviceTest < ActiveSupport::TestCase
    IOS_16 = "Mozilla/5.0 (iPhone; CPU iPhone OS 16_6 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/16.6 Mobile/15E148 Safari/604.1"
    IOS_17 = "Mozilla/5.0 (iPhone; CPU iPhone OS 17_4 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.4 Mobile/15E148 Safari/604.1"
    ANDROID_CHROME = "Mozilla/5.0 (Linux; Android 13; Pixel 7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Mobile Safari/537.36"
    OLD_FIREFOX = "Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:119.0) Gecko/20100101 Firefox/119.0"

    test "old iOS Safari is recognized and unsupported" do
      d = Device.parse(IOS_16)
      assert d.known?
      assert_equal "Safari", d.browser
      assert_equal false, d.supported?
    end

    test "current iOS Safari is supported" do
      assert_equal true, Device.parse(IOS_17).supported?
    end

    test "modern Android Chrome is supported" do
      d = Device.parse(ANDROID_CHROME)
      assert_equal "Chrome", d.browser
      assert_equal true, d.supported?
    end

    test "old Firefox is unsupported" do
      assert_equal false, Device.parse(OLD_FIREFOX).supported?
    end

    test "nil UA is unknown with a safe summary" do
      d = Device.parse(nil)
      assert_not d.known?
      assert_equal "Unknown device", d.summary
      assert_nil d.supported?
    end
  end
end
