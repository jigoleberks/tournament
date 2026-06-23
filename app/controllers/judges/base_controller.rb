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

  # Catches a judge of @tournament is allowed to see/act on:
  # anything placed in @tournament, plus the club-wide needs_review queue.
  def judgeable_catches
    placed_ids = CatchPlacement.where(tournament_id: @tournament.id).select(:catch_id)
    review_ids = Catch.where(status: :needs_review, user_id: @tournament.club.members.select(:id)).select(:id)
    # Eager-load the associations the index/show render per row: user + species
    # for the columns, catch_placements for visible_flags_for -> can_review_catch?,
    # and judge_actions for latest_approver. Without these the listing N+1s.
    Catch.where(id: placed_ids).or(Catch.where(id: review_ids))
         .includes(:user, :species, :catch_placements, :judge_actions)
  end

  def load_catch!
    @catch = judgeable_catches.find(params[:catch_id] || params[:id])
  end
end
