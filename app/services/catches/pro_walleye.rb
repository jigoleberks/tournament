require "bigdecimal"

module Catches
  # Classification + fixed limits for the Pro Walleye (Saskatchewan slot limit)
  # format: a five-fish Walleye basket in which at most 2 fish may be over 55 cm;
  # the remaining slots are filled with fish 55 cm and under. Centralized so
  # PlaceInSlots and ReconcileProWalleye share one threshold and one limit rule.
  module ProWalleye
    THRESHOLD_CM     = 55
    THRESHOLD_INCHES = (BigDecimal(THRESHOLD_CM.to_s) / BigDecimal("2.54"))
    BASKET_SIZE      = 5   # total fish that can count
    BIG_CAP          = 2   # of which at most 2 may be over 55 cm

    module_function

    # A Walleye longer than 55 cm is an "over" fish (at most BIG_CAP count); 55 cm
    # and under is an "under" fish. length_inches is decimal(5,2), so a fish
    # logged as exactly 55.0 cm stores 21.65 in — below the 21.6535 in threshold —
    # and correctly counts as an under fish.
    def big?(length_inches)
      length_inches.to_d > THRESHOLD_INCHES
    end
  end
end
