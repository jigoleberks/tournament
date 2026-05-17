module ConditionsHelper
  def format_temperature_dual(celsius)
    return "—" if celsius.nil?
    c = celsius.to_f
    f = c * 9.0 / 5.0 + 32
    "#{c.round(1)}°C / #{f.round(1)}°F"
  end

  def format_wind_dual(kph)
    return "—" if kph.nil?
    k = kph.to_f
    mph = k / 1.60934
    "#{k.round(1)} km/h / #{mph.round(1)} mph"
  end

  def format_wind_compass(deg)
    return nil if deg.nil?
    bins = %w[N NE E SE S SW W NW]
    bins[((deg.to_f + 22.5) / 45).floor % 8]
  end

  PRESSURE_TREND_THRESHOLD_HPA = 2.0

  def format_pressure_trend(delta_hpa)
    return nil if delta_hpa.nil?
    delta = delta_hpa.to_f
    return "steady" if delta.abs < PRESSURE_TREND_THRESHOLD_HPA
    direction = delta.positive? ? "rising" : "falling"
    "#{direction} #{(delta.abs / 10).round(1)} kPa over 24h"
  end
end
