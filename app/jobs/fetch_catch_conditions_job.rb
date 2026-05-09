require "net/http"
require "json"

class FetchCatchConditionsJob < ApplicationJob
  queue_as :default
  retry_on StandardError, wait: :polynomially_longer, attempts: 3

  OPEN_METEO_URL   = "https://api.open-meteo.com/v1/forecast"
  KNOWN_NEW_MOON   = Time.utc(2000, 1, 6, 18, 14).freeze
  LUNAR_CYCLE_DAYS = 29.530589

  def perform(catch_id:)
    catch_record = Catch.find_by(id: catch_id)
    return unless catch_record

    updates = {
      moon_phase:          moon_phase_name(catch_record.captured_at_device),
      moon_phase_fraction: moon_phase_fraction(catch_record.captured_at_device)
    }

    if catch_record.latitude.present? && catch_record.longitude.present?
      weather = fetch_weather(catch_record)
      updates.merge!(weather) if weather
    end

    catch_record.update_columns(updates)
  end

  private

  def fetch_weather(catch_record)
    captured_at = catch_record.captured_at_device.utc
    date_str    = captured_at.to_date.to_s

    uri = URI(OPEN_METEO_URL)
    uri.query = URI.encode_www_form(
      latitude:   catch_record.latitude.to_f,
      longitude:  catch_record.longitude.to_f,
      hourly:     "temperature_2m,surface_pressure,wind_speed_10m,wind_direction_10m",
      start_date: date_str,
      end_date:   date_str,
      timezone:   "UTC"
    )

    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl     = true
    http.open_timeout = 5
    http.read_timeout = 10

    response = http.get(uri.request_uri)
    return unless response.is_a?(Net::HTTPSuccess)

    data   = JSON.parse(response.body)
    hourly = data["hourly"]
    times  = hourly["time"]

    hour_str = captured_at.strftime("%Y-%m-%dT%H:00")
    idx = times.index(hour_str)
    return unless idx

    {
      temperature_c:           hourly["temperature_2m"][idx],
      barometric_pressure_hpa: hourly["surface_pressure"][idx],
      wind_speed_kph:          hourly["wind_speed_10m"][idx],
      wind_direction_deg:      hourly["wind_direction_10m"][idx]
    }
  end

  def moon_phase_fraction(time)
    elapsed = (time.utc - KNOWN_NEW_MOON) / 86400.0
    frac = (elapsed % LUNAR_CYCLE_DAYS) / LUNAR_CYCLE_DAYS
    frac < 0 ? frac + 1 : frac
  end

  def moon_phase_name(time)
    frac = moon_phase_fraction(time)
    case frac
    when 0...0.0625, 0.9375..1.0 then "New Moon"
    when 0.0625...0.1875          then "Waxing Crescent"
    when 0.1875...0.3125          then "First Quarter"
    when 0.3125...0.4375          then "Waxing Gibbous"
    when 0.4375...0.5625          then "Full Moon"
    when 0.5625...0.6875          then "Waning Gibbous"
    when 0.6875...0.8125          then "Last Quarter"
    when 0.8125...0.9375          then "Waning Crescent"
    end
  end
end
