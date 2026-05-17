require "test_helper"

class FetchCatchConditionsJobTest < ActiveJob::TestCase
  setup do
    @club = create(:club)
    @user = create(:user, club: @club)
    @species = create(:species, club: @club)
  end

  test "fetches pressure_msl (not surface_pressure) from Open-Meteo" do
    captured = Time.utc(2026, 5, 16, 14, 0)
    body = open_meteo_body(captured, [
      [-25, 1015.0], [-24, 1015.5], [-1, 1018.0], [0, 1019.5]
    ])

    requested_uri = nil
    stub_open_meteo(body, capture: ->(uri) { requested_uri = uri }) do
      run_job(captured)
    end

    assert_includes requested_uri.query, "pressure_msl"
    refute_includes requested_uri.query, "surface_pressure"
  end

  test "requests a 2-day window so the 24h-prior bucket is included" do
    captured = Time.utc(2026, 5, 16, 14, 0)
    body = open_meteo_body(captured, [[-24, 1015.0], [0, 1019.0]])

    requested_uri = nil
    stub_open_meteo(body, capture: ->(uri) { requested_uri = uri }) do
      run_job(captured)
    end

    params = URI.decode_www_form(requested_uri.query).to_h
    assert_equal "2026-05-15", params["start_date"]
    assert_equal "2026-05-16", params["end_date"]
  end

  test "stores barometric_pressure_hpa and a positive 24h trend when pressure rose" do
    captured = Time.utc(2026, 5, 16, 14, 0)
    body = open_meteo_body(captured, [[-24, 1015.0], [0, 1019.5]])

    catch_record = stub_open_meteo(body) { run_job(captured) }

    assert_equal 1019.5, catch_record.reload.barometric_pressure_hpa.to_f
    assert_in_delta 4.5, catch_record.pressure_trend_24h_hpa.to_f, 0.001
  end

  test "stores a negative 24h trend when pressure fell" do
    captured = Time.utc(2026, 5, 16, 14, 0)
    body = open_meteo_body(captured, [[-24, 1020.0], [0, 1014.0]])

    catch_record = stub_open_meteo(body) { run_job(captured) }

    assert_in_delta(-6.0, catch_record.reload.pressure_trend_24h_hpa.to_f, 0.001)
  end

  test "leaves pressure_trend_24h_hpa nil when the 24h-prior bucket is missing" do
    captured = Time.utc(2026, 5, 16, 14, 0)
    body = open_meteo_body(captured, [[0, 1019.0]])

    catch_record = stub_open_meteo(body) { run_job(captured) }

    assert_equal 1019.0, catch_record.reload.barometric_pressure_hpa.to_f
    assert_nil catch_record.pressure_trend_24h_hpa
  end

  private

  def run_job(captured)
    c = create(:catch,
      user: @user, species: @species,
      latitude: 49.33, longitude: -103.55,
      captured_at_device: captured
    )
    FetchCatchConditionsJob.perform_now(catch_id: c.id)
    c
  end

  # offsets_and_pressures: array of [hour_offset_from_captured, pressure_hpa]
  def open_meteo_body(captured, offsets_and_pressures)
    times      = offsets_and_pressures.map { |off, _| (captured + off.hours).strftime("%Y-%m-%dT%H:00") }
    pressures  = offsets_and_pressures.map { |_, p| p }
    placeholders = Array.new(offsets_and_pressures.size, nil)
    {
      "hourly" => {
        "time"               => times,
        "temperature_2m"     => placeholders,
        "pressure_msl"       => pressures,
        "wind_speed_10m"     => placeholders,
        "wind_direction_10m" => placeholders
      }
    }.to_json
  end

  def stub_open_meteo(body, capture: nil)
    fake_response = Object.new
    fake_response.define_singleton_method(:body) { body }
    fake_response.define_singleton_method(:is_a?) { |k| k == Net::HTTPSuccess || super(k) }

    fake_http = Object.new
    fake_http.define_singleton_method(:use_ssl=) { |_| }
    fake_http.define_singleton_method(:open_timeout=) { |_| }
    fake_http.define_singleton_method(:read_timeout=) { |_| }
    fake_http.define_singleton_method(:get) do |request_uri|
      capture&.call(URI("https://api.open-meteo.com#{request_uri}"))
      fake_response
    end

    original_new = Net::HTTP.method(:new)
    Net::HTTP.singleton_class.send(:remove_method, :new)
    Net::HTTP.define_singleton_method(:new) { |*_| fake_http }
    begin
      yield
    ensure
      Net::HTTP.singleton_class.send(:remove_method, :new)
      Net::HTTP.define_singleton_method(:new, original_new)
    end
  end
end
