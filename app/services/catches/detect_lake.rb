module Catches
  class DetectLake
    # Lake is metadata, not load-bearing — a malformed polygon JSON or registry
    # bug must never block a catch save. Swallow and log; the catch persists
    # with lake: nil and shows up under the "Other" filter.
    def self.call(catch_record)
      ::Geofence::Lakes.match(catch_record.latitude, catch_record.longitude)
    rescue StandardError => e
      Rails.logger.warn("Catches::DetectLake: #{e.class}: #{e.message}")
      nil
    end
  end
end
