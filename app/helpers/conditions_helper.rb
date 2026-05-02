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
end
