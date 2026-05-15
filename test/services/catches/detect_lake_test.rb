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
end
