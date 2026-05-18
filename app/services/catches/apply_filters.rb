module Catches
  class ApplyFilters
    def self.call(scope:, params:, time_zone: Time.zone)
      new(scope, params, time_zone).call
    end

    def initialize(scope, params, time_zone)
      @scope = scope
      @params = params
      @time_zone = time_zone
    end

    def call
      s = @scope
      s = apply_species(s)
      s = apply_lake(s)
      s = apply_month_or_date_range(s)
      s = apply_min_length(s)
      s = apply_wind_dir(s)
      s = apply_band(s, column: :wind_speed_kph,          bands: Catches::FilterBands::WIND_SPEED, param: :wind_speed)
      s = apply_band(s, column: :barometric_pressure_hpa, bands: Catches::FilterBands::PRESSURE,   param: :pressure)
      s = apply_moon(s)
      s = apply_time_of_day(s)
      s
    end

    private

    def apply_species(s)
      id = @params[:species].presence&.to_i
      id ? s.where(species_id: id) : s
    end

    def apply_lake(s)
      key = ::Geofence::Lakes.normalize_key(@params[:lake])
      return s if key.nil? || key == "all"
      return s.where(lake: nil) if key == "other"
      s.where(lake: key)
    end

    def apply_month_or_date_range(s)
      m = month_of_year
      return apply_month_of_year(s, m) if m
      apply_date_range(s)
    end

    def month_of_year
      m = @params[:month].to_i
      (1..12).include?(m) ? m : nil
    end

    def apply_month_of_year(s, m)
      # captured_at_device is `timestamp(6) without time zone`, storing UTC
      # values. The first AT TIME ZONE 'UTC' tags the naive timestamp as UTC
      # (yielding a timestamptz); the second converts to the app zone,
      # returning a naive local timestamp. EXTRACT then sees the correct
      # local month — a 10:30pm-local catch (4:30 UTC the next day) still
      # buckets to the prior local day's month.
      tz = @time_zone.tzinfo.name
      s.where(
        "EXTRACT(MONTH FROM (catches.captured_at_device AT TIME ZONE 'UTC' AT TIME ZONE ?)) = ?",
        tz, m
      )
    end

    def apply_date_range(s)
      start_param = @params[:start].presence
      end_param   = @params[:end].presence
      return s if start_param.nil? && end_param.nil?
      start_date = parse_date(start_param) || parse_date(end_param)
      finish_date = parse_date(end_param) || start_date
      return s if start_date.nil?
      start_date, finish_date = finish_date, start_date if start_date > finish_date
      s.where(captured_at_device: start_date.beginning_of_day..finish_date.end_of_day)
    end

    def apply_min_length(s)
      val = @params[:min_length].to_f
      val.positive? ? s.where("length_inches >= ?", val) : s
    end

    def apply_wind_dir(s)
      # Half-open interval [low, high): a catch at exactly the boundary
      # belongs to the next cardinal (e.g. 22.5° → NE, not N). Matches the
      # `format_wind_compass` helper's `((deg + 22.5) / 45).floor` convention.
      # Only the N band wraps (centre 0, low = -22.5); every other cardinal
      # in WIND_DIR_CENTRES has 0 <= low and high <= 360.
      key = @params[:wind_dir].presence
      centre = Catches::FilterBands::WIND_DIR_CENTRES[key]
      return s if centre.nil?
      half = Catches::FilterBands::WIND_DIR_HALF_WIDTH
      low  = centre - half
      high = centre + half
      if low < 0
        s.where("wind_direction_deg >= ? OR wind_direction_deg < ?", (low % 360), high)
      else
        s.where("wind_direction_deg >= ? AND wind_direction_deg < ?", low, high)
      end
    end

    def apply_band(s, column:, bands:, param:)
      key = @params[param].presence
      band = bands[key]
      return s if band.nil?
      conditions = []
      values = []
      if band[:min]
        op = band[:min_inclusive] == false ? ">" : ">="
        conditions << "#{column} #{op} ?"
        values << band[:min]
      end
      if band[:max]
        op = band[:max_inclusive] == false ? "<" : "<="
        conditions << "#{column} #{op} ?"
        values << band[:max]
      end
      return s if conditions.empty?
      # NULL columns drop out automatically — neither >= nor <= matches NULL.
      s.where(conditions.join(" AND "), *values)
    end

    def apply_moon(s)
      key = @params[:moon].presence
      band = Catches::FilterBands::MOON[key]
      return s if band.nil?
      if band == :new
        s.where("moon_phase_fraction < ? OR moon_phase_fraction >= ?", 0.125, 0.875)
      else
        # band is a Range like (0.125...0.375)
        s.where("moon_phase_fraction >= ? AND moon_phase_fraction < ?", band.begin, band.end)
      end
    end

    def apply_time_of_day(s)
      key = @params[:tod].presence
      hours = Catches::FilterBands::TIME_OF_DAY[key]
      return s if hours.nil?
      # See apply_month_of_year for why we need the double AT TIME ZONE
      # (captured_at_device is `timestamp without time zone` storing UTC).
      tz = @time_zone.tzinfo.name
      s.where(
        "EXTRACT(HOUR FROM (catches.captured_at_device AT TIME ZONE 'UTC' AT TIME ZONE ?)) IN (?)",
        tz, hours
      )
    end

    def parse_date(str)
      return nil if str.blank?
      Date.parse(str) rescue nil
    end
  end
end
