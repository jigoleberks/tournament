module Diagnostics
  # Read-only snapshot of what the server itself is running. Safe per-request.
  class ServerInfo
    def self.call
      new.to_h
    end

    def to_h
      {
        app_build:        ::AppVersion.current,
        ruby_version:     RUBY_VERSION,
        rails_version:    ::Rails.version,
        puma_version:     puma_version,
        postgres_version: postgres_version,
        rails_env:        ::Rails.env,
        booted_at:        booted_at
      }
    end

    private

    def puma_version
      defined?(::Puma::Const::VERSION) ? ::Puma::Const::VERSION : "unknown"
    end

    def postgres_version
      ::ActiveRecord::Base.connection.select_value("SHOW server_version").to_s.split.first.presence || "unknown"
    rescue StandardError
      "unknown"
    end

    # AppVersion captures a unix timestamp at module load (process boot).
    def booted_at
      ::Time.zone.at(::AppVersion.boot_fallback.to_i)
    rescue StandardError
      nil
    end
  end
end
