module Catches
  class ComputeFlags
    CLOCK_SKEW_THRESHOLD = 5.minutes

    def self.call(catch_record)
      flags = []
      flags << "missing_gps" if catch_record.latitude.nil?
      if catch_record.captured_at_device && catch_record.captured_at_gps
        skew = (catch_record.captured_at_device - catch_record.captured_at_gps).abs
        flags << "clock_skew" if skew > CLOCK_SKEW_THRESHOLD
      end
      if catch_record.latitude.present? && !Geofence.includes?(catch_record.latitude, catch_record.longitude)
        flags << "out_of_bounds"
      end
      flags
    end
  end
end
