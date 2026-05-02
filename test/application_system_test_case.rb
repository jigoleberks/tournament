require "test_helper"
require "capybara/cuprite"

Capybara.register_driver :tournament_cuprite do |app|
  # no-sandbox: Chromium's setuid sandbox can't run as root inside an unprivileged container.
  # disable-dev-shm-usage: /dev/shm in Docker defaults to 64MB, too small for Chromium tabs.
  Capybara::Cuprite::Driver.new(
    app,
    window_size: [1280, 800],
    headless: true,
    process_timeout: 30,
    browser_options: { "no-sandbox": nil, "disable-dev-shm-usage": nil }
  )
end

class ApplicationSystemTestCase < ActionDispatch::SystemTestCase
  driven_by :tournament_cuprite
end
