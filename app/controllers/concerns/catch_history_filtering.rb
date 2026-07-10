# Shared per-request filtering glue for the catch-history index pages — the
# personal "My catches" list and the club-scoped admin catch history. The actual
# predicates live in Catches::ApplyFilters; this concern resolves the
# date-range / sort / calendar params around it. It is parameterized by:
#   - the base relation each controller hands in (current_user.catches vs. the
#     club-scoped relation), and
#   - a #default_date_range hook each controller defines (personal defaults to a
#     single day; admin defaults to all dates).
module CatchHistoryFiltering
  extend ActiveSupport::Concern

  # Each includer MUST define this. Returns [start_date, end_date], or [nil, nil]
  # for "no default date filter". Used only when the request carries no explicit
  # ?start/?end and no ?month (month-of-year).
  def default_date_range
    raise NotImplementedError, "#{self.class} must define #default_date_range"
  end

  private

  def parse_date_range(params)
    start = Catches::ApplyFilters.parse_date(params[:start])
    finish = Catches::ApplyFilters.parse_date(params[:end]) || start
    return [nil, nil] if start.nil? && finish.nil?
    start ||= finish
    start, finish = finish, start if start > finish
    [start, finish]
  end

  # Thin wrapper so controllers (which also assign @month_of_year_active for the
  # calendar partial) share the service's predicate.
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
  # this pushes those resolved defaults back through to ApplyFilters when no
  # explicit ?start/?end was given.
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

  def counts_by_date(base_scope, month_start)
    # Group in Time.zone, not Postgres's session zone — DATE() on a UTC-stored
    # timestamp would mis-bucket evening catches in non-UTC deployments.
    range = month_start.beginning_of_day..month_start.end_of_month.end_of_day
    base_scope
      .where(captured_at_device: range)
      .pluck(:captured_at_device)
      .group_by { |t| t.in_time_zone.to_date }
      .transform_values(&:size)
  end
end
