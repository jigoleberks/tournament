module Catches
  class RebalanceSlots
    include SlotPlacement

    def self.call(tournament:, entry:, species:)
      new(tournament: tournament, entry: entry, species: species).call
    end

    def initialize(tournament:, entry:, species:)
      @tournament = tournament
      @entry = entry
      @species = species
    end

    def call
      # Each swap! is two writes (deactivate the old placement, then activate
      # or create the candidate's). Wrap so a mid-swap failure rolls back to
      # a consistent state. Rails flattens to a savepoint when the caller
      # (e.g. ApplyJudgeAction) already has an outer transaction open.
      ActiveRecord::Base.transaction do
        @entry.lock!  # serialize with PlaceInSlots / PromoteBackup on the same entry

        loop do
          smallest = smallest_active_placement
          break if smallest.nil?

          candidate = find_candidate
          break if candidate.nil?
          break if candidate.length_inches.to_f <= smallest.catch.length_inches.to_f

          swap!(smallest, candidate)
        end
      end
    end

    private

    def smallest_active_placement
      @entry.catch_placements
            .where(species_id: @species.id, active: true)
            .includes(:catch)
            .min_by { |p| p.catch.length_inches.to_f }
    end

    def find_candidate
      placed_ids = @entry.catch_placements
                         .where(species_id: @species.id, active: true)
                         .pluck(:catch_id)
      ::Catch.where(user_id: entry_member_ids,
                    species_id: @species.id,
                    captured_at_device: tournament_window)
             .where.not(status: ::Catch.statuses[:disqualified])
             .where.not(id: placed_ids)
             .order(length_inches: :desc, captured_at_device: :asc)
             .detect { |c| slot_eligible?(c) }
    end

    def swap!(placement, candidate)
      placement.update!(active: false)
      activate_placement!(candidate, slot_index: placement.slot_index)
    end
  end
end
