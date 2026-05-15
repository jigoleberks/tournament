require "test_helper"

class Catches::DetectLakeTest < ActiveSupport::TestCase
  setup { Geofence::Lakes.reload! }

  def make_catch(lat:, lng:)
    Catch.new(latitude: lat, longitude: lng)
  end

  test "returns the lake key for a catch with GPS in a known polygon" do
    catch_record = make_catch(lat: 53.55, lng: -103.65)
    assert_equal "tobin", Catches::DetectLake.call(catch_record)
  end

  test "returns nil for a catch with no GPS" do
    catch_record = make_catch(lat: nil, lng: nil)
    assert_nil Catches::DetectLake.call(catch_record)
  end

  test "returns nil for a catch outside every polygon" do
    catch_record = make_catch(lat: 52.5, lng: -106.5)
    assert_nil Catches::DetectLake.call(catch_record)
  end

  test "returns nil and logs when the registry raises" do
    catch_record = make_catch(lat: 53.55, lng: -103.65)
    io = StringIO.new
    original_logger = Rails.logger
    Rails.logger = Logger.new(io)
    begin
      with_class_method_stub(Geofence::Lakes, :match, ->(_lat, _lng) { raise "registry exploded" }) do
        assert_nil Catches::DetectLake.call(catch_record)
      end
    ensure
      Rails.logger = original_logger
    end
    log = io.string
    assert_includes log, "Catches::DetectLake"
    assert_includes log, "registry exploded"
  end
end
