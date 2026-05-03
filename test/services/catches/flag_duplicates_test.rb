require "test_helper"

class Catches::FlagDuplicatesTest < ActiveSupport::TestCase
  setup do
    @club = create(:club)
    @user = create(:user, club: @club)
    @walleye = create(:species, club: @club)
  end

  test "flags neighbors within 90s and bumps synced status to needs_review" do
    now = Time.current
    earlier = create(:catch, user: @user, species: @walleye,
                              captured_at_device: now - 30.seconds, status: :synced)
    new_catch = create(:catch, user: @user, species: @walleye,
                                captured_at_device: now,
                                flags: ["possible_duplicate"])

    Catches::FlagDuplicates.call(catch: new_catch)
    earlier.reload
    assert_includes earlier.flags, "possible_duplicate"
    assert_equal "needs_review", earlier.status
  end

  test "leaves out-of-window neighbors alone" do
    now = Time.current
    far = create(:catch, user: @user, species: @walleye,
                          captured_at_device: now - 91.seconds, status: :synced)
    new_catch = create(:catch, user: @user, species: @walleye,
                                captured_at_device: now,
                                flags: ["possible_duplicate"])

    Catches::FlagDuplicates.call(catch: new_catch)
    far.reload
    assert_not_includes far.flags, "possible_duplicate"
    assert_equal "synced", far.status
  end

  test "leaves catches by other users alone" do
    now = Time.current
    other = create(:user, club: @club)
    foreign = create(:catch, user: other, species: @walleye,
                              captured_at_device: now - 30.seconds, status: :synced)
    new_catch = create(:catch, user: @user, species: @walleye,
                                captured_at_device: now,
                                flags: ["possible_duplicate"])

    Catches::FlagDuplicates.call(catch: new_catch)
    foreign.reload
    assert_not_includes foreign.flags, "possible_duplicate"
  end

  test "preserves non-synced statuses on neighbor" do
    now = Time.current
    earlier = create(:catch, user: @user, species: @walleye,
                              captured_at_device: now - 30.seconds, status: :disqualified)
    new_catch = create(:catch, user: @user, species: @walleye,
                                captured_at_device: now,
                                flags: ["possible_duplicate"])

    Catches::FlagDuplicates.call(catch: new_catch)
    earlier.reload
    assert_includes earlier.flags, "possible_duplicate"
    assert_equal "disqualified", earlier.status
  end

  test "does not duplicate the flag if neighbor already carries it" do
    now = Time.current
    earlier = create(:catch, user: @user, species: @walleye,
                              captured_at_device: now - 30.seconds,
                              flags: ["possible_duplicate"], status: :needs_review)
    new_catch = create(:catch, user: @user, species: @walleye,
                                captured_at_device: now,
                                flags: ["possible_duplicate"])

    Catches::FlagDuplicates.call(catch: new_catch)
    earlier.reload
    assert_equal 1, earlier.flags.count("possible_duplicate")
  end
end
