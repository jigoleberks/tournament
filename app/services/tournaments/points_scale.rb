module Tournaments
  class PointsScale
    def self.call(angler_count:)
      case angler_count
      when 0..2   then nil
      when 3..9   then [3, 2, 1]
      when 10..19 then [6, 4, 2]
      else             [9, 6, 3]
      end
    end
  end
end
