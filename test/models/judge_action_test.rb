require "test_helper"

class JudgeActionTest < ActiveSupport::TestCase
  setup do
    @club = create(:club)
    @judge = create(:user, club: @club, role: :organizer)
    @catch = create(:catch, user: create(:user, club: @club),
                    species: create(:species, club: @club))
  end

  test "records action, note, before/after" do
    a = JudgeAction.create!(
      judge_user: @judge, catch: @catch, action: :approve,
      note: "looks good", before_state: { status: "needs_review" },
      after_state: { status: "synced" }
    )
    assert a.persisted?
    assert_equal "approve", a.action
    assert_equal "looks good", a.note
  end

  test "action enum covers approve, flag, disqualify, manual_override, dock_verify" do
    JudgeAction.actions.keys.tap do |keys|
      %w[approve flag disqualify manual_override dock_verify].each do |k|
        assert_includes keys, k
      end
    end
  end

  test "new correction actions are valid enum values" do
    %i[geofence_override correct_location reinstate].each do |a|
      action = build(:judge_action, action: a)
      assert action.valid?, "#{a} should be a valid action"
      assert_equal a.to_s, action.action
    end
  end
end
