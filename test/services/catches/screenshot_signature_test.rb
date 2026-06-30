require "test_helper"

class Catches::ScreenshotSignatureTest < ActiveSupport::TestCase
  def catch_with(file:)
    blob = ActiveStorage::Blob.create_and_upload!(
      io: File.open(Rails.root.join("test/fixtures/files/#{file}")),
      filename: file,
      content_type: "image/jpeg"
    )
    catch_record = Catch.new
    catch_record.photo.attach(blob)
    catch_record
  end

  test "detects a progressive JPEG as a screenshot signature" do
    catch_record = catch_with(file: "screenshot_progressive.jpg")
    assert Catches::ScreenshotSignature.call(catch_record)
  end

  test "does not flag a baseline JPEG (camera/transcode output)" do
    catch_record = catch_with(file: "sample_walleye.jpg")
    refute Catches::ScreenshotSignature.call(catch_record)
  end

  test "returns false when no photo is attached" do
    refute Catches::ScreenshotSignature.call(Catch.new)
  end
end
