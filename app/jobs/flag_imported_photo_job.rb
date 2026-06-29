class FlagImportedPhotoJob < ApplicationJob
  queue_as :default

  # A live photo's EXIF capture time lands within seconds of when the catch
  # was logged (take photo -> fill length -> submit). An imported gallery
  # photo carries a much earlier capture time. Flag for judge review when the
  # gap exceeds this window. Soft posture: flag, don't block.
  IMPORT_WINDOW = 5.minutes

  def perform(catch_id:)
    catch_record = Catch.find_by(id: catch_id)
    return unless catch_record&.photo&.attached?
    return if catch_record.flags.include?("imported_photo")
    return unless catch_record.captured_at_device

    captured_at = Catches::PhotoCaptureTime.call(catch_record)
    return if captured_at.nil? # no usable EXIF capture time — can't tell
    return if (catch_record.captured_at_device - captured_at).abs <= IMPORT_WINDOW

    # Bump an auto-synced catch into review so staff see the import flag — but
    # never override a human decision. A synced catch a judge has already acted
    # on was deliberately approved; re-opening it here would silently undo the
    # approval (and leave no JudgeAction trail), so only bump untouched catches.
    bump = catch_record.status == "synced" && !catch_record.judge_actions.exists?
    catch_record.add_flag!("imported_photo", bump_to_review: bump)
  end
end
