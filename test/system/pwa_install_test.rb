require "application_system_test_case"

class PwaInstallTest < ApplicationSystemTestCase
  test "manifest is linked from the layout" do
    visit "/"
    assert_selector "link[rel='manifest'][href='/manifest.webmanifest']", visible: false
  end

  test "manifest is served and parses as JSON" do
    skip "public/manifest.webmanifest is per-club and untracked (see 484c3e6); CI checkout has no manifest on disk."
    manifest_path = Rails.root.join("public/manifest.webmanifest")
    assert manifest_path.exist?, "Manifest file does not exist"

    content = File.read(manifest_path)
    parsed = JSON.parse(content)
    assert_equal "Tournament", parsed["short_name"]
  end
end
