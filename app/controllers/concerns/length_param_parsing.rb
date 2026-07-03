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

  def resolved_length_inches
    if params[:length].present?
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
end
