module Catches
  class RebalanceSlots
    def self.call(tournament:, entry:, species:)
      new(tournament: tournament, entry: entry, species: species).call
    end

    def initialize(tournament:, entry:, species:)
      @tournament = tournament
      @entry = entry
      @species = species
    end

    def call
      loop do
        smallest = smallest_active_placement
        break if smallest.nil?

        candidate = find_candidate
        break if candidate.nil?
        break if candidate.length_inches.to_f <= smallest.catch.length_inches.to_f

        swap!(smallest, candidate)
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
      ::Catches::EntryEligibility
        .candidates_for(entry: @entry, tournament: @tournament, species: @species)
        .find { |c| !placed_ids.include?(c.id) }
    end

    def swap!(placement, candidate)
      placement.update!(active: false)
      existing = ::CatchPlacement.find_by(
        catch_id: candidate.id, tournament_entry_id: @entry.id,
        species_id: @species.id, slot_index: placement.slot_index
      )
      if existing
        existing.update!(active: true)
      else
        ::CatchPlacement.create!(
          catch: candidate, tournament: @tournament, tournament_entry: @entry,
          species: @species, slot_index: placement.slot_index, active: true
        )
      end
    end
  end
end
