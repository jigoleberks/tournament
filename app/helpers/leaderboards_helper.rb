module LeaderboardsHelper
  # Display score for one Leaderboards::Build row, per tournament format.
  # Mirrors the score cell in tournaments/_leaderboard.html.erb (and the
  # ticket count in _tagged_leaderboard.html.erb) so the print sheet can't
  # drift from the on-screen leaderboard.
  def leaderboard_score_label(row, tournament)
    scoring_value = row[:total]
    bvs = tournament.format_biggest_vs_smallest?
    bvs_complete_zero = bvs && row[:complete] && scoring_value == 0

    return "—" if scoring_value.nil? || (scoring_value.zero? && !bvs_complete_zero)
    return "#{scoring_value} #{'ticket'.pluralize(scoring_value)}" if tournament.format_tagged?

    inches_part, = format_length_parts(scoring_value)
    cm_total = total_display_cm(row[:fish], biggest_vs_smallest: bvs)
    label = %(#{inches_part} · #{format('%.2f', cm_total)} cm)

    if tournament.format_hidden_length? && tournament.hidden_length_target.present?
      off = (scoring_value.to_d - tournament.hidden_length_target.to_d).abs
      label += %( · #{format('%.2f', off)}" off)
    end
    label
  end
end
