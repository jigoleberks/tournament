class NotificationSettingsController < ApplicationController
  before_action :require_sign_in!
  before_action :load_subs

  def show
    @tournaments = current_club.tournaments.where("ends_at IS NULL OR ends_at >= ?", Time.current)
  end

  def snooze
    hours = params[:hours].to_f
    @subs.update_all(muted_until: hours.hours.from_now)
    redirect_to notification_settings_path, notice: "Muted for #{hours}h."
  end

  def unmute
    @subs.update_all(muted_until: nil)
    redirect_to notification_settings_path, notice: "Notifications on."
  end

  def mute_tournament
    tid = params[:tournament_id].to_i
    # Each subscription carries its own muted_tournament_ids array, so we update
    # per row — but in one transaction so a mid-loop failure doesn't half-apply.
    ActiveRecord::Base.transaction do
      @subs.each do |sub|
        sub.update!(muted_tournament_ids: (sub.muted_tournament_ids + [tid]).uniq)
      end
    end
    redirect_to notification_settings_path
  end

  def unmute_tournament
    tid = params[:tournament_id].to_i
    ActiveRecord::Base.transaction do
      @subs.each do |sub|
        sub.update!(muted_tournament_ids: sub.muted_tournament_ids - [tid])
      end
    end
    redirect_to notification_settings_path
  end

  private

  def load_subs
    @subs = current_user.push_subscriptions
  end
end
