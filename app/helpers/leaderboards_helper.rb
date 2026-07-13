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
    # Progressive Length's "total" is an up-size count, not a length.
    return { up_sizes: scoring_value } if tournament&.format_progressive_length?

    inches_part, = format_length_parts(scoring_value)
    off = nil
    if tournament&.format_hidden_length? && tournament.hidden_length_target.present?
      off = (scoring_value.to_d - tournament.hidden_length_target.to_d).abs
    elsif tournament&.format_beat_the_average?
      off = row[:distance]   # present only on revealed (per-catch) rows
    elsif tournament&.format_random_bag?
      off = row[:distance]   # |bag_sum - team target|
    end
    cm = if tournament&.format_beat_the_average?
      # The shown inches is either the entry's average (play) or a single catch
      # length (reveal); derive cm from that same value so the two units agree.
      scoring_value.to_f * LengthHelper::CM_PER_INCH
    else
      total_display_cm(row[:fish], biggest_vs_smallest: bvs)
    end
    { inches: inches_part, cm: cm, off: off }
  end

  # Flat one-line score label for the admin/print results sheet.
  def leaderboard_score_label(row, tournament)
    return bingo_score_label(row) if tournament&.format_bingo?

    parts = leaderboard_score_parts(row, tournament)
    return "—" if parts.nil?
    return "#{parts[:tickets]} #{'ticket'.pluralize(parts[:tickets])}" if parts.key?(:tickets)
    return "#{parts[:up_sizes]} #{'up-size'.pluralize(parts[:up_sizes])}" if parts.key?(:up_sizes)

    label = %(#{parts[:inches]} · #{format('%.2f', parts[:cm])} cm)
    label += %( · #{format('%.2f', parts[:off])}" off) if parts[:off]
    label
  end

  # Bingo has no length "score" — the print sheet shows progress instead. An entry
  # holding only the free centre square (squares <= 1) hasn't progressed, so it
  # reads as "—" like a length entry with no scoring fish (mirrors QualifiedRows).
  def bingo_score_label(row)
    return "Blackout" if row[:blackout]
    squares = row[:squares_count].to_i
    return "—" if squares <= 1
    bingo_progress_label(lines_count: row[:lines_count].to_i, squares_count: squares)
  end

  # The shared "N line(s) · M/25 squares" fragment — single source of truth for the
  # progress wording, rendered by both the print/admin score sheet (bingo_score_label)
  # and the live card (_bingo_card partial).
  def bingo_progress_label(lines_count:, squares_count:)
    %(#{pluralize(lines_count, "line")} · #{squares_count}/25 squares)
  end
end
