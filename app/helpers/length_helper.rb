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

  # The numeric cm a fish displays, matching format_length_parts: a cm-logged
  # fish keeps its quarter-cm grid value; an inch-logged fish shows the exact
  # conversion (2 dp). Avoids the round-trip drift of reconverting stored inches.
  def display_cm(inches, unit)
    cm = inches.to_f * CM_PER_INCH
    unit == "centimeters" ? snap_quarter(cm) : cm.round(2)
  end

  # cm for the leaderboard score/total, combined from each fish's *displayed* cm
  # so a fish's cm never disagrees between its chip and the score column. BvS is
  # a spread (biggest − smallest); every other non-tagged format is a sum.
  def total_display_cm(fish, biggest_vs_smallest: false)
    return 0.0 if fish.blank?
    if biggest_vs_smallest
      return 0.0 if fish.size < 2
      display_cm(fish.first[:length_inches], fish.first[:length_unit]) -
        display_cm(fish.last[:length_inches], fish.last[:length_unit])
    else
      fish.sum { |f| display_cm(f[:length_inches], f[:length_unit]) }
    end
  end

  # A filename-safe single token in the logged unit, e.g. "50 in" or "50 cm".
  # No quote/slash characters, unlike format_length_dual.
  def length_token(inches, unit)
    return nil if inches.nil?
    i = inches.to_f
    if unit == "centimeters"
      "#{trim_measure(snap_quarter(i * CM_PER_INCH))} cm"
    else
      "#{trim_measure(i)} in"
    end
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
