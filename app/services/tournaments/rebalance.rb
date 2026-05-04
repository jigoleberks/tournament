module Tournaments
  class Rebalance
    def self.call(tournament:)
      new(tournament: tournament).call
    end

    def initialize(tournament:)
      @tournament = tournament
    end

    def call
      ActiveRecord::Base.transaction do
        rebalance_scoring_slots!
        deactivate_orphan_species_placements!
      end
      Placements::BroadcastLeaderboard.call(tournament: @tournament)
    end

    private

    def rebalance_scoring_slots!
      @tournament.scoring_slots.includes(:species).each do |slot|
        @tournament.tournament_entries.each do |entry|
          reconcile(entry: entry, slot: slot)
        end
      end
    end

    def reconcile(entry:, slot:)
      candidates = ::Catches::EntryEligibility.candidates_for(
        entry: entry, tournament: @tournament, species: slot.species
      ).first(slot.slot_count)

      desired_by_slot = candidates.each_with_index.to_h { |c, i| [i, c] }

      existing = entry.catch_placements
                      .where(species_id: slot.species_id)
                      .to_a

      desired_by_slot.each do |slot_index, catch_record|
        row = existing.find { |p| p.catch_id == catch_record.id && p.slot_index == slot_index }
        if row
          row.update!(active: true) unless row.active?
        else
          ::CatchPlacement.create!(
            catch: catch_record, tournament: @tournament, tournament_entry: entry,
            species: slot.species, slot_index: slot_index, active: true
          )
        end
      end

      desired_ids = desired_by_slot.map { |i, c| [c.id, i] }.to_set
      existing.each do |p|
        next if desired_ids.include?([p.catch_id, p.slot_index])
        p.update!(active: false) if p.active?
      end
    end

    def deactivate_orphan_species_placements!
      slot_species_ids = @tournament.scoring_slots.pluck(:species_id)
      @tournament.catch_placements
                 .where(active: true)
                 .where.not(species_id: slot_species_ids)
                 .update_all(active: false)
    end
  end
end
