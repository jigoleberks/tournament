module Catches
  module DetectLake
    module_function

    def call(catch_record)
      ::Geofence::Lakes.match(catch_record.latitude, catch_record.longitude)
    end
  end
end
