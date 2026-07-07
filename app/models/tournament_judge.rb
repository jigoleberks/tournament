class TournamentJudge < ApplicationRecord
  belongs_to :tournament
  belongs_to :user
  validates :user_id, uniqueness: { scope: :tournament_id }
  validate :user_not_an_entrant

  private

  # The mirror of TournamentEntryMember#user_not_a_judge: someone entered in the
  # tournament can't also judge it.
  def user_not_an_entrant
    return if tournament_id.nil? || user_id.nil?

    entered = TournamentEntryMember
      .joins(:tournament_entry)
      .where(tournament_entries: { tournament_id: tournament_id }, user_id: user_id)
      .exists?

    errors.add(:user, "is entered in this tournament and can't judge it") if entered
  end
end
