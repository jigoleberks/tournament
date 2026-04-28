require "test_helper"

class Organizers::TournamentTemplatesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @club = create(:club)
    @organizer = create(:user, club: @club, role: :organizer)
    sign_in_as(@organizer)
  end

  test "POST clone creates a tournament" do
    walleye = create(:species, club: @club)
    template = create(:tournament_template, club: @club, name: "Monthly Walleye")
    template.tournament_template_scoring_slots.create!(species: walleye, slot_count: 1)

    assert_difference "Tournament.count", 1 do
      post clone_organizers_tournament_template_path(template),
           params: { starts_at: 1.day.from_now, ends_at: 1.day.from_now + 4.hours }
    end
    assert_redirected_to organizers_tournaments_path
  end

  private

  def sign_in_as(user)
    token = SignInToken.issue!(user: user)
    get consume_session_path(token: token.token)
  end
end
