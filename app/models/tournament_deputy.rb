# A temporary, tournament-scoped organizer grant. A deputy holds full organizer
# access only until their tournament starts — at kickoff they become a
# competitor again. Expiry is evaluated on read (see User#active_deputy_in?),
# so there is no expiry job and nothing to clean up.
class TournamentDeputy < ApplicationRecord
  belongs_to :tournament
  belongs_to :user
  belongs_to :granted_by_user, class_name: "User"

  validates :user_id, uniqueness: { scope: :tournament_id }

  # NOTE: deliberately no `user_not_an_entrant` validation, unlike
  # TournamentJudge. A deputy helps build the field for the tournament they
  # then fish in; organizers are already allowed to compete.

  scope :live, -> { joins(:tournament).where("tournaments.starts_at > ?", Time.current) }
end
