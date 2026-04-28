require "application_system_test_case"

class SmokeTest < ApplicationSystemTestCase
  test "the root URL returns a 200" do
    visit "/"
    assert_equal 200, page.status_code
  end
end
