require "test_helper"

class FlagImportedPhotoJobTest < ActiveJob::TestCase
  # sample_with_exif.jpg carries a fixed EXIF DateTimeOriginal/OffsetTimeOriginal.
  # We vary captured_at_device around it to exercise the import window without
  # stubbing — so the real EXIF-extraction path is covered too.
  EXIF_TIME = Time.new(2020, 1, 1, 12, 0, 0, "-06:00")

  setup do
    @club = create(:club)
    @user = create(:user, club: @club)
    @judge = create(:user, club: @club, role: :organizer)
    @species = create(:species, club: @club)
  end

  def catch_with(file:, captured_at:, status: :synced, flags: [])
    catch_record = create(:catch, user: @user, species: @species,
                                  captured_at_device: captured_at, status: status, flags: flags)
    blob = ActiveStorage::Blob.create_and_upload!(
      io: File.open(Rails.root.join("test/fixtures/files/#{file}")),
      filename: file,
      content_type: "image/jpeg"
    )
    catch_record.photo.attach(blob)
    catch_record
  end

  test "flags imported_photo and bumps a synced catch to needs_review when the gap exceeds 5 min" do
    catch_record = catch_with(file: "sample_with_exif.jpg", captured_at: EXIF_TIME + 1.hour)

    FlagImportedPhotoJob.perform_now(catch_id: catch_record.id)

    catch_record.reload
    assert_includes catch_record.flags, "imported_photo"
    assert_equal "needs_review", catch_record.status
  end

  test "does not flag when the photo was captured within 5 min of submission (live)" do
    catch_record = catch_with(file: "sample_with_exif.jpg", captured_at: EXIF_TIME + 2.minutes)

    FlagImportedPhotoJob.perform_now(catch_id: catch_record.id)

    catch_record.reload
    refute_includes catch_record.flags, "imported_photo"
    assert_equal "synced", catch_record.status
  end

  test "does not flag when there is no usable EXIF capture time" do
    catch_record = catch_with(file: "sample_walleye.jpg", captured_at: Time.utc(2026, 6, 1, 12, 0, 0))

    FlagImportedPhotoJob.perform_now(catch_id: catch_record.id)

    assert_empty catch_record.reload.flags
  end

  test "is idempotent — re-running does not add a duplicate flag" do
    catch_record = catch_with(file: "sample_with_exif.jpg", captured_at: EXIF_TIME + 1.hour,
                              status: :needs_review, flags: ["imported_photo"])

    FlagImportedPhotoJob.perform_now(catch_id: catch_record.id)

    assert_equal ["imported_photo"], catch_record.reload.flags
  end

  test "adds the flag but preserves a non-synced status (e.g. disqualified)" do
    catch_record = catch_with(file: "sample_with_exif.jpg", captured_at: EXIF_TIME + 1.hour,
                              status: :disqualified)

    FlagImportedPhotoJob.perform_now(catch_id: catch_record.id)

    catch_record.reload
    assert_includes catch_record.flags, "imported_photo"
    assert_equal "disqualified", catch_record.status
  end

  test "does not reopen a judge-approved (synced) catch, but still records the flag" do
    catch_record = catch_with(file: "sample_with_exif.jpg", captured_at: EXIF_TIME + 1.hour, status: :synced)
    JudgeAction.create!(judge_user: @judge, catch: catch_record, action: :approve)

    FlagImportedPhotoJob.perform_now(catch_id: catch_record.id)

    catch_record.reload
    assert_includes catch_record.flags, "imported_photo", "still surfaces the import flag for staff"
    assert_equal "synced", catch_record.status, "must not undo a judge's approval"
  end

  test "flags screenshot_suspect and bumps a synced catch to needs_review for a progressive JPEG" do
    catch_record = catch_with(file: "screenshot_progressive.jpg", captured_at: Time.utc(2026, 6, 1, 12, 0, 0))

    FlagImportedPhotoJob.perform_now(catch_id: catch_record.id)

    catch_record.reload
    assert_includes catch_record.flags, "screenshot_suspect"
    assert_equal "needs_review", catch_record.status
  end

  test "does not flag screenshot_suspect for a baseline JPEG" do
    catch_record = catch_with(file: "sample_walleye.jpg", captured_at: Time.utc(2026, 6, 1, 12, 0, 0))

    FlagImportedPhotoJob.perform_now(catch_id: catch_record.id)

    refute_includes catch_record.reload.flags, "screenshot_suspect"
  end

  test "is idempotent — re-running does not add a duplicate screenshot_suspect flag" do
    catch_record = catch_with(file: "screenshot_progressive.jpg", captured_at: Time.utc(2026, 6, 1, 12, 0, 0),
                              status: :needs_review, flags: ["screenshot_suspect"])

    FlagImportedPhotoJob.perform_now(catch_id: catch_record.id)

    assert_equal ["screenshot_suspect"], catch_record.reload.flags
  end

  test "records screenshot_suspect but does not reopen a judge-approved (synced) catch" do
    catch_record = catch_with(file: "screenshot_progressive.jpg", captured_at: Time.utc(2026, 6, 1, 12, 0, 0))
    JudgeAction.create!(judge_user: @judge, catch: catch_record, action: :approve)

    FlagImportedPhotoJob.perform_now(catch_id: catch_record.id)

    catch_record.reload
    assert_includes catch_record.flags, "screenshot_suspect"
    assert_equal "synced", catch_record.status
  end

  test "does nothing for a missing catch id" do
    assert_nothing_raised { FlagImportedPhotoJob.perform_now(catch_id: -1) }
  end
end
