module Catches
  class ComputeFlags
    CLOCK_SKEW_THRESHOLD = 5.minutes
    DUPLICATE_WINDOW = 90.seconds

    def self.call(catch_record)
      flags = []
      flags << "missing_gps" if catch_record.latitude.nil?
      if catch_record.captured_at_device && catch_record.captured_at_gps
        skew = (catch_record.captured_at_device - catch_record.captured_at_gps).abs
        flags << "clock_skew" if skew > CLOCK_SKEW_THRESHOLD
      end
      if catch_record.latitude.present? && !::Geofence.includes?(:lake, catch_record.latitude, catch_record.longitude)
        flags << "out_of_bounds"
      end
      flags << "possible_duplicate" if duplicate_neighbor?(catch_record)
      flags
    end

    def self.duplicate_neighbor?(catch_record)
      return false if catch_record.user_id.nil? || catch_record.captured_at_device.nil?
      window = (catch_record.captured_at_device - DUPLICATE_WINDOW)..(catch_record.captured_at_device + DUPLICATE_WINDOW)
      scope = ::Catch.where(user_id: catch_record.user_id, captured_at_device: window)
      scope = scope.where.not(id: catch_record.id) if catch_record.id
      scope.exists?
    end
  end
end
