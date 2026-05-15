module Catches
  class DetectLake
    def self.call(catch_record)
      ::Geofence::Lakes.match(catch_record.latitude, catch_record.longitude)
    end
  end
end
