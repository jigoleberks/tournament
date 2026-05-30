module CatchFilterHelpers
  extend ActiveSupport::Concern

  private

  def parse_date_range(params)
    start = Catches::ApplyFilters.parse_date(params[:start])
    finish = Catches::ApplyFilters.parse_date(params[:end]) || start
    return [nil, nil] if start.nil? && finish.nil?
    start ||= finish
    start, finish = finish, start if start > finish
    [start, finish]
  end

  def default_date_range
    today = Date.current
    if current_user.catches.where(captured_at_device: today.beginning_of_day..today.end_of_day).exists?
      [today, today]
    elsif (latest = current_user.catches.maximum(:captured_at_device))
      d = latest.to_date
      [d, d]
    else
      [nil, nil]
    end
  end

  # Thin wrapper so the controller (which also assigns @month_of_year_active
  # for the calendar partial) shares the service's predicate.
  def month_of_year_param
    Catches::ApplyFilters.month_of_year(params)
  end

  def resolve_date_range
    return [nil, nil] if month_of_year_param  # month-of-year wins
    if params.key?(:start) || params.key?(:end)
      parse_date_range(params)
    else
      default_date_range
    end
  end

  # Returns the params hash the service should see. The controller resolves
  # date-range defaults itself (so the calendar agrees with the catches list);
  # this method exists to push those resolved defaults back through to
  # ApplyFilters when no explicit ?start/?end was given.
  #
  # Truth table for what we pass to the service:
  #   month=valid       → params unchanged (service handles month-of-year)
  #   start or end set  → params unchanged (explicit user intent wins)
  #   no catches at all → params unchanged (no default range to inject)
  #   otherwise         → params + injected :start/:end from default_date_range
  def effective_filter_params
    return params if month_of_year_param
    return params if params.key?(:start) || params.key?(:end)
    return params if @selected_start.nil?
    params.merge(start: @selected_start.iso8601, end: @selected_end.iso8601)
  end

  def sort_catches(scope)
    case @sort
    when :longest  then scope.order(length_inches: :desc, captured_at_device: :desc)
    when :shortest then scope.order(length_inches: :asc, captured_at_device: :desc)
    else                scope.order(captured_at_device: :desc)
    end
  end

  def counts_by_date(month_start)
    # Group in Time.zone, not Postgres's session zone — DATE() on a UTC-stored
    # timestamp would mis-bucket evening catches in non-UTC deployments.
    range = month_start.beginning_of_day..month_start.end_of_month.end_of_day
    current_user.catches
      .where(captured_at_device: range)
      .pluck(:captured_at_device)
      .group_by { |t| t.in_time_zone.to_date }
      .transform_values(&:size)
  end
end
