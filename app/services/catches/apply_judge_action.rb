module Catches
  class ApplyJudgeAction
    class SelfApprovalError < StandardError; end
    class DisqualifyNoteRequired < StandardError; end

    def self.call(tournament:, catch:, judge:, action:, note: nil,
                  length_inches: nil, species_id: nil, slot_index: nil, entry_id: nil)
      new(tournament: tournament, catch: catch, judge: judge, action: action, note: note,
          length_inches: length_inches, species_id: species_id,
          slot_index: slot_index, entry_id: entry_id).call
    end

    def initialize(tournament:, catch:, judge:, action:, note:, length_inches:, species_id:, slot_index:, entry_id:)
      @tournament, @catch, @judge, @action, @note = tournament, catch, judge, action.to_sym, note
      @length_inches, @species_id, @slot_index, @entry_id = length_inches, species_id, slot_index, entry_id
    end

    def call
      raise SelfApprovalError if @action == :approve && @judge.id == @catch.user_id
      raise DisqualifyNoteRequired if @action == :disqualify && @note.to_s.strip.empty?

      affected_tournaments = []

      ActiveRecord::Base.transaction do
        @catch.lock!  # serialize with PlaceInSlots on the same catch
        before = snapshot
        case @action
        when :approve, :dock_verify
          @catch.update!(status: :synced)
        when :flag
          @catch.update!(status: :needs_review)
        when :disqualify
          # Lock affected entries in id order so concurrent PlaceInSlots /
          # other judge actions don't deadlock with us.
          entry_ids = @catch.catch_placements.active.pluck(:tournament_entry_id).uniq.sort
          entry_ids.each { |id| TournamentEntry.lock.find(id) }

          freed = @catch.catch_placements.active.to_a
          @catch.catch_placements.active.update_all(active: false)
          @catch.update!(status: :disqualified)
          freed.each do |p|
            p.reload
            Catches::PromoteBackup.call(freed_placement: p)
          end
        when :manual_override
          prior_length  = @catch.length_inches
          prior_species = @catch.species_id

          # Order: length first, then species, then slot-force / length-shrink rebalance.
          # Length must update before the species-change block so PlaceInSlots ranks the
          # catch with its NEW length when looking for slots in the new species.
          @catch.update!(length_inches: @length_inches) if @length_inches

          if @species_id && @species_id != prior_species
            # Lock affected entries in id order so concurrent PlaceInSlots / other
            # judge actions don't deadlock with us. Mirrors the disqualify path.
            entry_ids = @catch.catch_placements.active.pluck(:tournament_entry_id).uniq.sort
            entry_ids.each { |id| TournamentEntry.lock.find(id) }

            freed = @catch.catch_placements.active.to_a
            @catch.catch_placements.active.update_all(active: false)
            @catch.update!(species_id: @species_id)
            freed.each do |p|
              p.reload
              Catches::PromoteBackup.call(freed_placement: p)
            end

            # Re-place the catch under the new species. PlaceInSlots will only
            # place in tournaments where the user has an entry at captured_at_device
            # AND there's a scoring slot for the new species; otherwise the catch
            # stays unplaced.
            # broadcast: false — we're inside ApplyJudgeAction's outer transaction.
            # The caller's post-transaction broadcast at the bottom of #call covers
            # any newly-affected tournaments. Broadcasting here would expose
            # pre-commit state to subscribers via separate DB connections.
            Catches::PlaceInSlots.call(catch: @catch, broadcast: false)
          end

          if @slot_index && @entry_id
            entry = @tournament.tournament_entries.find(@entry_id)
            entry.lock!
            # Deactivate whatever is currently in (entry, species, slot_index)
            entry.catch_placements
              .where(species: @catch.species, slot_index: @slot_index, active: true)
              .update_all(active: false)
            CatchPlacement.create!(
              catch: @catch, tournament: @tournament, tournament_entry: entry,
              species: @catch.species, slot_index: @slot_index, active: true
            )
          elsif @length_inches && prior_length && @length_inches.to_f < prior_length.to_f
            # Length shrank — re-evaluate every (entry, species) pair this catch
            # is currently placed in; a previously-unplaced larger catch should
            # take its slot. Sort by entry id for stable lock order.
            @catch.catch_placements.active.includes(:tournament, :tournament_entry).order(:tournament_entry_id).each do |p|
              Catches::RebalanceSlots.call(tournament: p.tournament, entry: p.tournament_entry, species: @catch.species)
            end
          end
        end
        after = snapshot

        JudgeAction.create!(
          judge_user: @judge, catch: @catch, action: @action, note: @note,
          before_state: before, after_state: after
        )

        affected_tournaments = @catch.catch_placements.map(&:tournament).uniq
      end

      # Broadcast AFTER the transaction commits so other DB connections see the
      # new state when they rebuild the leaderboard.
      affected_tournaments.each do |t|
        Placements::BroadcastLeaderboard.call(tournament: t)
      end
    end

    private

    def snapshot
      species = Species.find_by(id: @catch.species_id)
      {
        "status"            => @catch.status,
        "length_inches"     => @catch.length_inches.to_s,
        "species_id"        => @catch.species_id,
        "species_name"      => species&.name,
        "active_placements" => @catch.catch_placements.where(active: true).pluck(:tournament_entry_id, :slot_index)
      }
    end
  end
end
