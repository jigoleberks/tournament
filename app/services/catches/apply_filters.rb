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
      s
    end

    private

    def apply_species(s)
      id = @params[:species].presence&.to_i
      id ? s.where(species_id: id) : s
    end

    def apply_lake(s)
      key = normalized_lake_filter
      return s if key.nil? || key == "all"
      return s.where(lake: nil) if key == "other"
      s.where(lake: key)
    end

    def normalized_lake_filter
      raw = @params[:lake].presence
      return nil if raw.nil?
      return raw if raw == "all" || raw == "other"
      ::Geofence::Lakes.known_key?(raw) ? raw : nil
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

    def parse_date(str)
      return nil if str.blank?
      Date.parse(str) rescue nil
    end
  end
end
