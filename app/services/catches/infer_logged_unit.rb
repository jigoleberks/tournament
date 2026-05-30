module Catches
  class InferLoggedUnit
    # Returns "inches" or "centimeters" for a stored length_inches value.
    # A quarter-cm measurement never lands on an exact quarter-inch, so an
    # off-grid value was almost certainly entered in cm. On-grid values default
    # to inches unless the logging user prefers cm.
    def self.call(length_inches:, user_length_unit: nil)
      return "inches" if length_inches.nil?
      hundredths = (BigDecimal(length_inches.to_s) * 100).to_i
      on_quarter_inch = (hundredths % 25).zero?
      return "centimeters" unless on_quarter_inch
      user_length_unit == "centimeters" ? "centimeters" : "inches"
    end
  end
end
