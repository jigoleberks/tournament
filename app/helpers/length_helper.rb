module LengthHelper
  CM_PER_INCH = 2.54

  # Inches -> "22.0\" / 55.9 cm"
  def format_length_dual(inches)
    return "—" if inches.nil?
    inches_f = inches.to_f
    cm = inches_f * CM_PER_INCH
    "#{inches_f.round(2)}\" / #{cm.round(1)} cm"
  end

  # Inches -> ["22.0\"", "55.9 cm"]
  def format_length_parts(inches)
    return ["—", ""] if inches.nil?
    inches_f = inches.to_f
    cm = inches_f * CM_PER_INCH
    ["#{inches_f.round(2)}\"", "#{cm.round(1)} cm"]
  end
end
