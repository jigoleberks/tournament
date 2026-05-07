module ApplicationHelper
  def tournament_window(tournament)
    starts_at = tournament.starts_at
    ends_at   = tournament.ends_at
    return nil if starts_at.blank?

    if ends_at.blank?
      format_tournament_moment(starts_at)
    elsif starts_at.to_date == ends_at.to_date
      "#{format_tournament_moment(starts_at)} – #{ends_at.strftime("%l:%M %p").strip}"
    else
      "#{format_tournament_moment(starts_at)} – #{format_tournament_moment(ends_at)}"
    end
  end

  private

  def format_tournament_moment(time)
    fmt = time.year == Time.current.year ? "%b %-d · %l:%M %p" : "%b %-d, %Y · %l:%M %p"
    time.strftime(fmt).squeeze(" ")
  end
end
