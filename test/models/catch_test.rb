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

  test "rejects a non-image photo content_type" do
    catch_record = build(:catch, user: @user, species: @walleye)
    catch_record.photo.attach(
      io: StringIO.new("not really an image"),
      filename: "evil.txt",
      content_type: "text/plain"
    )
    assert_not catch_record.valid?
    assert_includes catch_record.errors[:photo].join, "JPEG"
  end

  test "rejects a photo larger than the byte cap" do
    catch_record = build(:catch, user: @user, species: @walleye)
    catch_record.photo.attach(
      io: StringIO.new("x" * (Catch::PHOTO_MAX_BYTES + 1)),
      filename: "huge.jpg",
      content_type: "image/jpeg"
    )
    assert_not catch_record.valid?
    assert_includes catch_record.errors[:photo].join, "larger"
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

  test "bass over 35 inches is invalid" do
    bass = create(:species, club: @club, name: "Bass")
    too_big = build(:catch, user: @user, species: bass, length_inches: 35.25)
    assert_not too_big.valid?
    assert_includes too_big.errors[:length_inches].join, "Bass"
  end

  test "lake trout over 55 inches is invalid" do
    trout = create(:species, club: @club, name: "Lake Trout")
    too_big = build(:catch, user: @user, species: trout, length_inches: 55.5)
    assert_not too_big.valid?
  end

  test "stocked trout over 35 inches is invalid" do
    trout = create(:species, club: @club, name: "Stocked Trout")
    too_big = build(:catch, user: @user, species: trout, length_inches: 35.25)
    assert_not too_big.valid?
  end

  test "tagged walleye over 50 inches is invalid" do
    tagged = create(:species, club: @club, name: "Tagged Walleye")
    too_big = build(:catch, user: @user, species: tagged, length_inches: 50.5,
                    tag_number: "A1")
    assert_not too_big.valid?
  end

  test "other over 200 inches is invalid" do
    other = create(:species, club: @club, name: "Other")
    too_big = build(:catch, user: @user, species: other, length_inches: 200.25)
    assert_not too_big.valid?
  end

  test "other at exactly 200 inches is valid" do
    other = create(:species, club: @club, name: "Other")
    boundary = build(:catch, user: @user, species: other, length_inches: 200)
    assert boundary.valid?
  end

  test "a species not in the cap table accepts any positive length" do
    crappie = create(:species, club: @club, name: "Crappie")
    big = build(:catch, user: @user, species: crappie, length_inches: 500)
    assert big.valid?
  end

  test "length_cap_for looks up the cap by species name, case-insensitive" do
    assert_equal 50, Catch.length_cap_for(@walleye)
    assert_equal 35, Catch.length_cap_for(create(:species, club: @club, name: "Bass"))
    assert_nil Catch.length_cap_for(create(:species, club: @club, name: "Crappie"))
    assert_nil Catch.length_cap_for(nil)
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

  test "disqualification_note breaks created_at ties deterministically by highest id" do
    judge = create(:user, club: @club, role: :organizer)
    catch_record = create(:catch, user: @user, species: @walleye, status: :disqualified)
    same_time = 1.minute.ago
    create(:judge_action, catch: catch_record, judge_user: judge, action: :disqualify,
                          note: "earlier row", created_at: same_time)
    create(:judge_action, catch: catch_record, judge_user: judge, action: :disqualify,
                          note: "later row", created_at: same_time)
    assert_equal "later row", catch_record.disqualification_note
  end

  test "disqualification_note consumes eager-loaded judge_actions without re-querying" do
    judge = create(:user, club: @club, role: :organizer)
    2.times do
      c = create(:catch, user: @user, species: @walleye, status: :disqualified)
      create(:judge_action, catch: c, judge_user: judge, action: :disqualify, note: "bad")
    end

    loaded = Catch.where(status: :disqualified).includes(:judge_actions).to_a
    judge_action_queries = count_queries(/\bfrom\s+"?judge_actions"?/i) do
      loaded.each(&:disqualification_note)
    end
    assert_equal 0, judge_action_queries,
                 "disqualification_note should read the preloaded association, not re-query per row"
  end

  test "disqualification_note returns nil when catch is not disqualified" do
    judge = create(:user, club: @club, role: :organizer)
    catch_record = create(:catch, user: @user, species: @walleye, status: :needs_review)
    create(:judge_action, catch: catch_record, judge_user: judge, action: :disqualify, note: "stale")
    assert_nil catch_record.disqualification_note
  end

  test "tag_number is normalized to uppercase before validation" do
    user = create(:user)
    tagged = Species.find_or_create_by!(name: "Tagged Walleye")
    c = build(:catch, user: user, species: tagged, tag_number: "a1234", length_inches: 18.0)
    c.valid?
    assert_equal "A1234", c.tag_number
  end

  test "tag_number is required when species is Tagged Walleye" do
    user = create(:user)
    tagged = Species.find_or_create_by!(name: "Tagged Walleye")
    c = build(:catch, user: user, species: tagged, tag_number: nil, length_inches: 18.0)
    assert_not c.valid?
    assert_includes c.errors[:tag_number], "is required for Tagged Walleye catches"
  end

  test "tag_number is not required when species is not Tagged Walleye" do
    user = create(:user)
    walleye = create(:species, name: "Walleye Test #{SecureRandom.hex(2)}")
    c = build(:catch, user: user, species: walleye, tag_number: nil, length_inches: 18.0)
    assert c.valid?, c.errors.full_messages.to_sentence
  end

  test "tag_number must match [A-Z0-9-] format" do
    user = create(:user)
    tagged = Species.find_or_create_by!(name: "Tagged Walleye")
    c = build(:catch, user: user, species: tagged, tag_number: "abc 123!", length_inches: 18.0)
    assert_not c.valid?
    assert_includes c.errors[:tag_number], "may only contain letters, numbers, and dashes"
  end

  test "tag_number max length is 16" do
    user = create(:user)
    tagged = Species.find_or_create_by!(name: "Tagged Walleye")
    c = build(:catch, user: user, species: tagged, tag_number: "A" * 17, length_inches: 18.0)
    assert_not c.valid?
    assert(c.errors[:tag_number].any? { |m| m.include?("16") })
  end

  test "weight_text is optional even for Tagged Walleye" do
    user = create(:user)
    tagged = Species.find_or_create_by!(name: "Tagged Walleye")
    c = build(:catch, user: user, species: tagged, tag_number: "A1", weight_text: nil, length_inches: 18.0)
    assert c.valid?, c.errors.full_messages.to_sentence
  end

  test "weight_text accepts freeform values verbatim" do
    user = create(:user)
    tagged = Species.find_or_create_by!(name: "Tagged Walleye")
    ["4 lbs 3oz", "2.1kg", "approx 2kg!?", "3 pounds"].each do |value|
      c = build(:catch, user: user, species: tagged, tag_number: "A1", weight_text: value, length_inches: 18.0)
      assert c.valid?, "expected #{value.inspect} to be valid: #{c.errors.full_messages.to_sentence}"
      assert_equal value, c.weight_text
    end
  end

  test "weight_text max length is 32" do
    user = create(:user)
    tagged = Species.find_or_create_by!(name: "Tagged Walleye")
    c = build(:catch, user: user, species: tagged, tag_number: "A1", weight_text: "x" * 33, length_inches: 18.0)
    assert_not c.valid?
    assert(c.errors[:weight_text].any? { |m| m.include?("32") })
  end

  test "weight_text is trimmed and whitespace-only becomes nil" do
    user = create(:user)
    tagged = Species.find_or_create_by!(name: "Tagged Walleye")

    c1 = build(:catch, user: user, species: tagged, tag_number: "A1", weight_text: "  4 lbs 3oz  ", length_inches: 18.0)
    c1.valid?
    assert_equal "4 lbs 3oz", c1.weight_text

    c2 = build(:catch, user: user, species: tagged, tag_number: "A1", weight_text: "   ", length_inches: 18.0)
    c2.valid?
    assert_nil c2.weight_text
  end

  test "length_unit must be inches or centimeters" do
    c = build(:catch, length_unit: "furlongs")
    assert_not c.valid?
    assert_includes c.errors[:length_unit], "is not included in the list"
  end

  test "missing length_unit is inferred from the value on validation" do
    c = build(:catch, length_inches: 6.99, length_unit: nil)
    c.valid?
    assert_equal "centimeters", c.length_unit
  end

  test "missing length_unit on an on-grid value defaults to inches" do
    c = build(:catch, length_inches: 18.5, length_unit: nil)
    c.valid?
    assert_equal "inches", c.length_unit
  end
end
