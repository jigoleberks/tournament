module Catches
  class PromoteBackup
    include SlotPlacement

    def self.call(freed_placement:)
      new(freed_placement: freed_placement).call
    end

    def initialize(freed_placement:)
      @placement  = freed_placement
      @tournament = freed_placement.tournament
      @entry      = freed_placement.tournament_entry
      @species    = freed_placement.species
      @slot_index = freed_placement.slot_index
    end

    def call
      ActiveRecord::Base.transaction do
        @entry.lock!  # serialize with PlaceInSlots / ReconcileStandard on the same entry

        candidate = find_candidate
        return nil if candidate.nil?
        activate_placement!(candidate, slot_index: @slot_index)
      end
    end

    private

    def find_candidate
      placed_ids = @entry.catch_placements
                          .where(species_id: @species.id, active: true)
                          .pluck(:catch_id)
      excluded_ids = (placed_ids + [ @placement.catch_id ]).uniq
      ::Catch.where(user_id: entry_member_ids,
                    species_id: @species.id,
                    captured_at_device: tournament_window)
             .where.not(status: ::Catch.statuses[:disqualified])
             .where.not(id: excluded_ids)
             .order(length_inches: :desc, captured_at_device: :asc)
             .detect { |c| slot_eligible?(c) }
    end
  end
end
