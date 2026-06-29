class Judges::BaseController < ApplicationController
  before_action :require_sign_in!
  before_action :load_tournament
  before_action :require_judge!

  # Every judge action funnels through Catches::ApplyJudgeAction; turn the errors
  # it can raise into a friendly redirect back to the catch instead of a raw
  # error page. RecordNotFound is intentionally left alone so cross-tournament
  # access still 404s.
  rescue_from Catches::ApplyJudgeAction::SelfApprovalError do
    redirect_to_loaded_catch(alert: "You can't approve your own catch.")
  end
  rescue_from Catches::ApplyJudgeAction::DisqualifyNoteRequired do
    redirect_to_loaded_catch(alert: "A reason note is required to disqualify a catch.")
  end
  rescue_from ActiveRecord::RecordInvalid do |error|
    raise error unless @catch
    redirect_to_loaded_catch(alert: "Couldn't apply that change: #{error.record.errors.full_messages.to_sentence}")
  end

  private

  def redirect_to_loaded_catch(alert:)
    redirect_to judges_tournament_catch_path(tournament_id: @tournament.id, id: @catch.id), alert: alert
  end

  def load_tournament
    @tournament = current_club.tournaments.find(params[:tournament_id])
  end

  def require_judge!
    return if TournamentJudge.exists?(tournament: @tournament, user: current_user)
    return if @tournament.friendly? && current_user.organizer_in?(@tournament.club)
    head :forbidden
  end

  # Like require_judge!, but also lets site admins (who needn't be assigned as a
  # judge) act. Organizers remain limited to friendly tournaments, matching
  # require_judge!. Used for the catch index/detail and the correction actions.
  def require_reviewer!
    return if TournamentJudge.exists?(tournament: @tournament, user: current_user)
    return if @tournament.friendly? && current_user.organizer_in?(@tournament.club)
    return if current_user.admin?
    head :forbidden
  end

  # Catches a judge of @tournament is allowed to see/act on:
  # anything placed in @tournament, plus the club-wide needs_review queue.
  def judgeable_catches
    placed_ids = CatchPlacement.where(tournament_id: @tournament.id).select(:catch_id)
    club_member_ids = @tournament.club.members.select(:id)
    review_ids = Catch.where(status: :needs_review, user_id: club_member_ids).select(:id)
    # Eager-load the associations the index/show render per row: user + species
    # for the columns, catch_placements for visible_flags_for -> can_review_catch?,
    # and judge_actions for latest_approver. Without these the listing N+1s.
    Catch.where(id: placed_ids).or(Catch.where(id: review_ids))
         .includes(:user, :species, :catch_placements, :judge_actions)
  end

  # Catch lookup for the detail page and correction actions. Broader than
  # judgeable_catches (the index queue) so that a catch disqualified while it
  # was still in needs_review and never placed remains reachable for reinstate.
  # A previously-placed DQ'd catch is already covered by placed_ids (which
  # deliberately doesn't filter on active:), so we only add the club-wide
  # disqualified set here, NOT in the index listing.
  def load_catch!
    placed_ids = CatchPlacement.where(tournament_id: @tournament.id).select(:catch_id)
    club_member_ids = @tournament.club.members.select(:id)
    @catch = Catch.where(id: placed_ids)
                  .or(Catch.where(status: :needs_review, user_id: club_member_ids))
                  .or(Catch.where(status: :disqualified, user_id: club_member_ids))
                  .includes(:user, :species, :catch_placements, :judge_actions)
                  .find(params[:catch_id] || params[:id])
  end
end
