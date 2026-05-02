class TournamentEntryMember < ApplicationRecord
  MAX_TEAM_MEMBERS = 5

  belongs_to :tournament_entry
  belongs_to :user

  validate :respect_team_cap
  validate :user_not_already_in_tournament

  private

  def respect_team_cap
    return if tournament_entry.nil?

    siblings_count = tournament_entry.tournament_entry_members.where.not(id: id).count
    case tournament_entry.tournament.mode
    when "solo"
      if siblings_count >= 1
        errors.add(:base, "solo entries have exactly 1 angler")
      end
    when "team"
      if siblings_count >= MAX_TEAM_MEMBERS
        errors.add(:base, "team is at capacity (#{MAX_TEAM_MEMBERS} anglers max)")
      end
    end
  end

  def user_not_already_in_tournament
    return if tournament_entry.nil? || user.nil?

    tournament_id = tournament_entry.tournament_id
    already_in = TournamentEntryMember
      .joins(:tournament_entry)
      .where(tournament_entries: { tournament_id: tournament_id }, user_id: user.id)
      .where.not(id: id)
      .exists?

    errors.add(:user, "is already entered in this tournament") if already_in
  end
end
