require "application_system_test_case"

class SwRegistrationTest < ApplicationSystemTestCase
  test "service worker registers on first visit" do
    visit "/"
    # Poll getRegistrations() since the register() promise resolution is delayed in Cuprite.
    # getRegistrations() reflects actual browser state immediately after install.
    count = 0
    Timeout.timeout(10) do
      loop do
        page.evaluate_script(
          "navigator.serviceWorker.getRegistrations().then(rs => { window.__swRegCount = rs.length; })"
        )
        sleep 0.3
        count = page.evaluate_script("window.__swRegCount || 0").to_i
        break if count > 0
      end
    end
    assert count >= 1, "service worker did not register (getRegistrations returned #{count})"
  end
end
