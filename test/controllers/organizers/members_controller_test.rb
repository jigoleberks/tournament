require "test_helper"

class Organizers::MembersControllerTest < ActionDispatch::IntegrationTest
  setup do
    @club = create(:club)
    @organizer = create(:user, club: @club, role: :organizer)
    sign_in_as(@organizer)
  end

  test "creating a member sends an invitation email containing a magic link" do
    assert_difference -> { User.count } => 1, -> { SignInToken.count } => 1 do
      assert_emails 1 do
        post organizers_members_path, params: {
          user: { name: "New Guy", email: "new@example.com", role: "member" }
        }
      end
    end
    assert_match SignInToken.last.token, ActionMailer::Base.deliveries.last.body.encoded
  end

  private

  def sign_in_as(user)
    token = SignInToken.issue!(user: user)
    get consume_session_path(token: token.token)
  end
end
