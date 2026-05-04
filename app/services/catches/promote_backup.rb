module Catches
  class PromoteBackup
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
      candidate = find_candidate
      return nil if candidate.nil?
      existing = ::CatchPlacement.find_by(
        catch_id: candidate.id, tournament_entry_id: @entry.id,
        species_id: @species.id, slot_index: @slot_index
      )
      if existing
        existing.update!(active: true)
        existing
      else
        ::CatchPlacement.create!(
          catch: candidate, tournament: @tournament, tournament_entry: @entry,
          species: @species, slot_index: @slot_index, active: true
        )
      end
    end

    private

    def find_candidate
      placed_ids = @entry.catch_placements
                         .where(species_id: @species.id, active: true)
                         .pluck(:catch_id)
      ::Catches::EntryEligibility
        .candidates_for(entry: @entry, tournament: @tournament, species: @species)
        .find { |c| !placed_ids.include?(c.id) && c.id != @placement.catch_id }
    end
  end
end
