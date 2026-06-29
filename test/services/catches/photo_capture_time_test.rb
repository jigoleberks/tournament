require "test_helper"

class Catches::PhotoCaptureTimeTest < ActiveSupport::TestCase
  def catch_with(file:, content_type:)
    blob = ActiveStorage::Blob.create_and_upload!(
      io: File.open(Rails.root.join("test/fixtures/files/#{file}")),
      filename: file,
      content_type: content_type
    )
    catch_record = Catch.new
    catch_record.photo.attach(blob)
    catch_record
  end

  test "reads the absolute capture time from EXIF DateTimeOriginal + offset" do
    catch_record = catch_with(file: "sample_with_exif.jpg", content_type: "image/jpeg")
    assert_equal Time.new(2020, 1, 1, 12, 0, 0, "-06:00"),
                 Catches::PhotoCaptureTime.call(catch_record)
  end

  test "returns nil when the photo has no EXIF capture metadata" do
    catch_record = catch_with(file: "sample_walleye.jpg", content_type: "image/jpeg")
    assert_nil Catches::PhotoCaptureTime.call(catch_record)
  end

  test "returns nil when no photo is attached" do
    assert_nil Catches::PhotoCaptureTime.call(Catch.new)
  end
end
