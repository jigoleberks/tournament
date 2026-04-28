require "test_helper"

class NotificationSettingsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = create(:user)
    @sub = create(:push_subscription, user: @user)
    sign_in_as(@user)
  end

  test "POST /notification_settings/snooze sets muted_until" do
    post snooze_notification_settings_path, params: { hours: 4 }
    @sub.reload
    assert_in_delta 4.hours.from_now, @sub.muted_until, 60
  end

  test "POST /notification_settings/unmute clears muted_until" do
    @sub.update!(muted_until: 4.hours.from_now)
    post unmute_notification_settings_path
    assert_nil @sub.reload.muted_until
  end

  test "POST /notification_settings/mute_tournament adds the tournament id" do
    t = create(:tournament)
    post mute_tournament_notification_settings_path, params: { tournament_id: t.id }
    assert_includes @sub.reload.muted_tournament_ids, t.id
  end

  test "POST /notification_settings/unmute_tournament removes the tournament id" do
    t = create(:tournament)
    @sub.update!(muted_tournament_ids: [t.id])
    post unmute_tournament_notification_settings_path, params: { tournament_id: t.id }
    assert_not_includes @sub.reload.muted_tournament_ids, t.id
  end

  private

  def sign_in_as(user)
    token = SignInToken.issue!(user: user)
    get consume_session_path(token: token.token)
  end
end
