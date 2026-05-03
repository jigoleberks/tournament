require "test_helper"

class CatchTest < ActiveSupport::TestCase
  setup do
    @club = create(:club)
    @user = create(:user, club: @club)
    @walleye = create(:species, club: @club, name: "Walleye")
  end

  test "requires user, species, length_inches, captured_at_device" do
    assert_not Catch.new.valid?
  end

  test "length must be positive" do
    catch_record = build(:catch, user: @user, species: @walleye, length_inches: 0)
    assert_not catch_record.valid?
  end

  test "status defaults to synced (no offline in this phase)" do
    catch_record = create(:catch, user: @user, species: @walleye)
    assert catch_record.synced?
  end

  test "client_uuid must be unique" do
    create(:catch, user: @user, species: @walleye, client_uuid: "abc")
    duplicate = build(:catch, user: @user, species: @walleye, client_uuid: "abc")
    assert_not duplicate.valid?
  end

  test "can attach a photo" do
    catch_record = build(:catch, user: @user, species: @walleye)
    catch_record.photo.attach(
      io: File.open(Rails.root.join("test/fixtures/files/sample_walleye.jpg")),
      filename: "sample_walleye.jpg",
      content_type: "image/jpeg"
    )
    assert catch_record.save
    assert catch_record.photo.attached?
  end

  test "walleye over 50 inches is invalid" do
    too_big = build(:catch, user: @user, species: @walleye, length_inches: 50.5)
    assert_not too_big.valid?
    assert_includes too_big.errors[:length_inches].join, "Walleye"
  end

  test "walleye at exactly 50 inches is valid" do
    boundary = build(:catch, user: @user, species: @walleye, length_inches: 50)
    assert boundary.valid?
  end

  test "perch over 20 inches is invalid" do
    perch = create(:species, club: @club, name: "Perch")
    too_big = build(:catch, user: @user, species: perch, length_inches: 20.25)
    assert_not too_big.valid?
  end

  test "pike over 70 inches is invalid" do
    pike = create(:species, club: @club, name: "Pike")
    too_big = build(:catch, user: @user, species: pike, length_inches: 70.5)
    assert_not too_big.valid?
  end

  test "uncapped species accept any positive length" do
    trout = create(:species, club: @club, name: "Lake Trout")
    big = build(:catch, user: @user, species: trout, length_inches: 200)
    assert big.valid?
  end

  test "note up to 500 chars is valid" do
    catch_record = build(:catch, user: @user, species: @walleye, note: "a" * 500)
    assert catch_record.valid?
  end

  test "note over 500 chars is invalid" do
    catch_record = build(:catch, user: @user, species: @walleye, note: "a" * 501)
    assert_not catch_record.valid?
    assert_includes catch_record.errors[:note].join, "too long"
  end

  test "note nil is valid" do
    catch_record = build(:catch, user: @user, species: @walleye, note: nil)
    assert catch_record.valid?
  end

  test "latest_approver returns the judge of the most recent approve action" do
    judge = create(:user, club: @club, role: :organizer, name: "Judy")
    catch_record = create(:catch, user: @user, species: @walleye, status: :needs_review)
    create(:judge_action, catch: catch_record, judge_user: judge, action: :approve)
    assert_equal judge, catch_record.latest_approver
  end

  test "latest_approver returns nil when no judge actions exist" do
    catch_record = create(:catch, user: @user, species: @walleye)
    assert_nil catch_record.latest_approver
  end

  test "latest_approver returns nil when most recent action is a flag" do
    judge = create(:user, club: @club, role: :organizer)
    catch_record = create(:catch, user: @user, species: @walleye, status: :needs_review)
    create(:judge_action, catch: catch_record, judge_user: judge, action: :approve, created_at: 2.minutes.ago)
    create(:judge_action, catch: catch_record, judge_user: judge, action: :flag, created_at: 1.minute.ago)
    assert_nil catch_record.latest_approver
  end

  test "disqualification_note returns the latest disqualify note when DQ'd" do
    judge = create(:user, club: @club, role: :organizer)
    catch_record = create(:catch, user: @user, species: @walleye, status: :disqualified)
    create(:judge_action, catch: catch_record, judge_user: judge, action: :disqualify, note: "blurry photo")
    assert_equal "blurry photo", catch_record.disqualification_note
  end

  test "disqualification_note returns the most recent of multiple DQ actions" do
    judge = create(:user, club: @club, role: :organizer)
    catch_record = create(:catch, user: @user, species: @walleye, status: :disqualified)
    create(:judge_action, catch: catch_record, judge_user: judge, action: :disqualify,
                          note: "first reason", created_at: 2.minutes.ago)
    create(:judge_action, catch: catch_record, judge_user: judge, action: :disqualify,
                          note: "actual reason", created_at: 1.minute.ago)
    assert_equal "actual reason", catch_record.disqualification_note
  end

  test "disqualification_note returns nil when catch is not disqualified" do
    judge = create(:user, club: @club, role: :organizer)
    catch_record = create(:catch, user: @user, species: @walleye, status: :needs_review)
    create(:judge_action, catch: catch_record, judge_user: judge, action: :disqualify, note: "stale")
    assert_nil catch_record.disqualification_note
  end
end
