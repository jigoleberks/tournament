# Controller-side parsing of a length form submission, shared by the judge
# manual-override and the organizer/admin catch edit. Accepts either the new
# form (length + length_unit, snapped to the 0.25 grid of the entered unit and
# converted to inches) or the legacy raw length_inches. (LengthHelper#snap_quarter
# is a view helper for a different, float-based display path — keep this
# BigDecimal request-parsing copy separate.)
module LengthParamParsing
  extend ActiveSupport::Concern

  QUARTER = BigDecimal("0.25")

  private

  def resolved_length_inches(catch = nil)
    if params[:length].present?
      # If the length field still holds exactly the value the editor prefilled
      # for this catch (same unit), the user changed something else (note,
      # species) and left length alone. Recomputing length_inches from a
      # prefilled value is lossy for catches whose stored inches aren't on the
      # display grid — legacy inch-logged fish mis-tagged cm, or any off-grid
      # value — so return the stored value verbatim rather than drifting it and
      # tripping a phantom length change (which would re-score and notify).
      return catch.length_inches if catch && length_field_untouched?(catch)

      raw = snap_quarter(params[:length].to_d)
      # length_inches is decimal(5,2). Round the cm->inch conversion to that same
      # scale so re-saving a catch's prefilled cm value round-trips to the stored
      # value instead of an un-rounded decimal (e.g. 55 cm -> 21.65, not
      # 21.6535…) that ApplyJudgeAction would mistake for a length edit.
      params[:length_unit] == "centimeters" ? (raw / LengthHelper::CM_PER_INCH).round(2) : raw
    else
      params[:length_inches]&.to_d
    end
  end

  def resolved_length_unit
    params[:length_unit] if %w[inches centimeters].include?(params[:length_unit])
  end

  def snap_quarter(value)
    (value / QUARTER).round * QUARTER
  end

  # True when params[:length] still equals the value the editor seeded the field
  # with for this catch, in the catch's own unit. Mirrors _organizer_editor's
  # prefill (LengthHelper#display_cm) arithmetic exactly — cm snapped to the 0.25
  # grid, inches as stored — so "the user didn't touch length" is detected
  # byte-for-byte, immune to the display grid's lossy round-trip.
  def length_field_untouched?(catch)
    return false if catch.length_inches.nil?
    return false unless params[:length_unit] == catch.length_unit

    prefill =
      if catch.length_unit == "centimeters"
        cm = catch.length_inches.to_f * LengthHelper::CM_PER_INCH
        (cm / LengthHelper::QUARTER_CM).round * LengthHelper::QUARTER_CM
      else
        catch.length_inches.to_f
      end
    params[:length].to_f == prefill
  end
end
