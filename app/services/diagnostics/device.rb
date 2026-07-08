require "useragent"

module Diagnostics
  # Read-only formatter over the `useragent` gem. `supported?` mirrors Rails'
  # `allow_browser versions: :modern` floors so the admin card can flag a member
  # whose browser is too old to even load the app. Keep these in sync with the
  # Rails default if it changes.
  class Device
    SUPPORTED_FLOORS = {
      "Safari"  => "17.2",
      "Chrome"  => "120",
      "Firefox" => "121",
      "Edge"    => "120",
      "Opera"   => "106"
    }.freeze

    def self.parse(ua_string)
      new(ua_string)
    end

    def initialize(ua_string)
      @raw   = ua_string.to_s
      @agent = ::UserAgent.parse(@raw) if @raw.present?
    end

    def known?
      @agent.present? && @agent.browser.present? && @agent.browser != "Other"
    end

    def browser = known? ? @agent.browser : "Unknown"
    def version = known? ? @agent.version.to_s : ""
    def os      = known? ? @agent.os.to_s : ""

    def summary
      return "Unknown device" unless known?
      label = [browser, version].reject(&:blank?).join(" ")
      os.present? ? "#{label} · #{os}" : label
    end

    # true = meets the modern floor, false = too old, nil = can't tell.
    def supported?
      return nil unless known?
      floor = SUPPORTED_FLOORS[@agent.browser]
      return nil unless floor && @agent.version
      @agent.version >= ::UserAgent::Version.new(floor)
    rescue StandardError
      nil
    end
  end
end
