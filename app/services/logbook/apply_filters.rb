module Logbook
  # Wraps Catches::ApplyFilters and tacks on the logbook-specific predicates
  # (structure enum, bait_id). Kept separate so the standard catches/map views
  # don't gain noise from filters that don't apply when the logbook is off.
  class ApplyFilters
    def self.call(scope:, params:, time_zone: Time.zone)
      scope = ::Catches::ApplyFilters.call(scope: scope, params: params, time_zone: time_zone)
      scope = apply_structure(scope, params)
      scope = apply_bait(scope, params)
      scope
    end

    def self.apply_structure(scope, params)
      key = params[:structure].to_s
      return scope unless Catch.structures.key?(key)
      scope.where(structure: key)
    end

    def self.apply_bait(scope, params)
      id = params[:bait_id].presence&.to_i
      return scope if id.nil? || id.zero?
      scope.where(bait_id: id)
    end
  end
end
