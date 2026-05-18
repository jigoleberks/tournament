module Catches
  module FilterBands
    WIND_DIR_CENTRES = {
      "n"  => 0,   "ne" => 45,  "e"  => 90,  "se" => 135,
      "s"  => 180, "sw" => 225, "w"  => 270, "nw" => 315
    }.freeze
    WIND_DIR_HALF_WIDTH = 22.5

    WIND_SPEED = {
      "calm"   => { min: nil,  max: 5,   max_inclusive: false },
      "light"  => { min: 5,    max: 15,  max_inclusive: true  },
      "mod"    => { min: 15,   max: 25,  max_inclusive: true, min_inclusive: false },
      "strong" => { min: 25,   max: nil, min_inclusive: false }
    }.freeze

    PRESSURE = {
      "low"    => { min: nil,    max: 1010, max_inclusive: false },
      "normal" => { min: 1010,   max: 1020, max_inclusive: true  },
      "high"   => { min: 1020,   max: nil,  min_inclusive: false }
    }.freeze

    MOON = {
      "new"  => :new,    # < 0.125 OR >= 0.875
      "q1"   => (0.125...0.375),
      "full" => (0.375...0.625),
      "q3"   => (0.625...0.875)
    }.freeze

    TIME_OF_DAY = {
      "dawn"     => [4, 5, 6],
      "morning"  => [7, 8, 9, 10],
      "noon"     => [11, 12, 13],
      "daylight" => [14, 15, 16],
      "evening"  => [17, 18, 19],
      "dusk"     => [20, 21, 22],
      "night"    => [23, 0, 1, 2, 3]
    }.freeze

    WIND_SPEED_LABELS = {
      "calm" => "Calm", "light" => "Light", "mod" => "Mod", "strong" => "Strong"
    }.freeze
    PRESSURE_LABELS = {
      "low" => "Low", "normal" => "Normal", "high" => "High"
    }.freeze
    MOON_LABELS = {
      "new" => "New", "q1" => "1Q", "full" => "Full", "q3" => "3Q"
    }.freeze
    TIME_OF_DAY_LABELS = {
      "dawn" => "Dawn", "morning" => "Morning", "noon" => "Noon",
      "daylight" => "Daylight", "evening" => "Evening", "dusk" => "Dusk", "night" => "Night"
    }.freeze
    WIND_DIR_LABELS = {
      "n" => "N", "ne" => "NE", "e" => "E", "se" => "SE",
      "s" => "S", "sw" => "SW", "w" => "W", "nw" => "NW"
    }.freeze
  end
end
