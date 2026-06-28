module LeaderboardsHelper
  # Score pieces for one Leaderboards::Build row, per tournament format. Single
  # source of truth shared by the on-screen leaderboard partial and the
  # print-sheet label below, so the two can't drift. Returns one of:
  #   nil                              → no score yet (render "—")
  #   { tickets: Integer }             → tagged format (ticket count)
  #   { inches:, cm:, off: }           → length formats; off is nil unless
  #                                      hidden-length with a target set.
  def leaderboard_score_parts(row, tournament)
    scoring_value = row[:total]
    bvs = tournament&.format_biggest_vs_smallest?
    bvs_complete_zero = bvs && row[:complete] && scoring_value == 0

    return nil if scoring_value.nil? || (scoring_value.zero? && !bvs_complete_zero)
    return { tickets: scoring_value } if tournament&.format_tagged?

    inches_part, = format_length_parts(scoring_value)
    off = nil
    if tournament&.format_hidden_length? && tournament.hidden_length_target.present?
      off = (scoring_value.to_d - tournament.hidden_length_target.to_d).abs
    end
    { inches: inches_part, cm: total_display_cm(row[:fish], biggest_vs_smallest: bvs), off: off }
  end

  # Flat one-line score label for the admin/print results sheet.
  def leaderboard_score_label(row, tournament)
    parts = leaderboard_score_parts(row, tournament)
    return "—" if parts.nil?
    return "#{parts[:tickets]} #{'ticket'.pluralize(parts[:tickets])}" if parts.key?(:tickets)

    label = %(#{parts[:inches]} · #{format('%.2f', parts[:cm])} cm)
    label += %( · #{format('%.2f', parts[:off])}" off) if parts[:off]
    label
  end
end
