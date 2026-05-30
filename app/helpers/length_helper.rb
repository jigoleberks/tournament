module LengthHelper
  CM_PER_INCH = 2.54
  QUARTER_CM = 0.25

  # `unit` is the unit the catch was logged in. The native unit renders its exact
  # 1/4-grid value with trailing zeros trimmed; the converted unit renders to 2 dp.
  # `unit` nil (totals, hidden-length targets) renders both units to 2 dp.
  def format_length_parts(inches, unit = nil)
    return ["—", ""] if inches.nil?
    i = inches.to_f
    case unit
    when "inches"
      [%(#{trim_measure(i)}"), "#{format('%.2f', i * CM_PER_INCH)} cm"]
    when "centimeters"
      [%(#{format('%.2f', i)}"), "#{trim_measure(snap_quarter(i * CM_PER_INCH))} cm"]
    else
      [%(#{format('%.2f', i)}"), "#{format('%.2f', i * CM_PER_INCH)} cm"]
    end
  end

  def format_length_dual(inches, unit = nil)
    inches_part, cm_part = format_length_parts(inches, unit)
    return "—" if cm_part.blank?
    "#{inches_part} / #{cm_part}"
  end

  private

  def snap_quarter(value)
    (value / QUARTER_CM).round * QUARTER_CM
  end

  def trim_measure(value)
    rounded = value.round(2)
    return rounded.to_i.to_s if rounded == rounded.to_i
    rounded.to_s.sub(/0+\z/, "")
  end
end
