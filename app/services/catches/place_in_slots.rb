module Catches
  class PlaceInSlots
    def self.call(catch:, broadcast: true)
      new(catch: catch, broadcast: broadcast).call
    end

    def initialize(catch:, broadcast: true)
      @catch = catch
      @broadcast = broadcast
    end

    def call
      created, bumped = [], []
      affected_tournaments = Set.new

      # One outer transaction so all locks acquired here are released atomically.
      # Without it, two boats submitting catches for the same (entry, species) at
      # the same instant could both observe `size < slot_count` and both create
      # placements at the same slot_index, corrupting the leaderboard.
      ActiveRecord::Base.transaction do
        @catch.lock!  # serialize with ApplyJudgeAction on the same catch
        return { created: [], bumped: [], affected_tournaments: [], submitter: @catch.user } if @catch.disqualified?

        rows = Tournaments::ActiveForUser
          .with_entries(user: @catch.user, at: @catch.captured_at_device)
          .sort_by { |r| r[:entry].id }  # stable lock order across concurrent calls

        rows.each do |row|
          tournament = row[:tournament]
          entry      = row[:entry]
          slot       = tournament.scoring_slots.find_by(species_id: @catch.species_id)
          next if slot.nil?
          next if skip_for_out_of_province?
          next if skip_for_local_out_of_bounds?(tournament)

          entry.lock!  # serialize with PromoteBackup, RebalanceSlots, other PlaceInSlots

          # Tournaments::ActiveForUser ran before the entry row lock was held, so a
          # concurrent DropMemberFromEntry could have removed the user from this entry
          # between resolution and lock acquisition. Re-verify membership now.
          next unless entry.tournament_entry_members.exists?(user_id: @catch.user_id)

          active_placements = entry.catch_placements
            .where(species_id: @catch.species_id, active: true)
            .includes(:catch).order(:slot_index).to_a

          if tournament.format_hidden_length?
            # Hidden Length: every catch is kept; the closest-to-target catch
            # per entry is selected at reveal time. No bumping, slot_count irrelevant.
            # Use max(active slot_index)+1 (not size) so a deactivated middle
            # placement (e.g. judge DQ) doesn't make the next index collide with
            # an existing active row under idx_active_placements_uniq_per_slot.
            next_index = active_placements.empty? ? 0 : active_placements.map(&:slot_index).max + 1
            created << CatchPlacement.create!(
              catch: @catch, tournament: tournament, tournament_entry: entry,
              species: @catch.species, slot_index: next_index, active: true
            )
            affected_tournaments << tournament
          elsif tournament.format_biggest_vs_smallest?
            # Biggest vs Smallest: keep at most 2 placements per (entry, species) — the
            # current biggest and current smallest. A new catch only matters if it's
            # MORE extreme than one of them. The previously-extreme placement is now
            # in the middle and gets dropped; the new catch reuses its slot_index.
            if active_placements.size < 2
              next_index = (0..1).find { |i| active_placements.none? { |p| p.slot_index == i } }
              created << CatchPlacement.create!(
                catch: @catch, tournament: tournament, tournament_entry: entry,
                species: @catch.species, slot_index: next_index, active: true
              )
              affected_tournaments << tournament
            else
              sorted = active_placements.sort_by { |p| p.catch.length_inches }
              min_p, max_p = sorted.first, sorted.last
              if @catch.length_inches > max_p.catch.length_inches
                max_p.update!(active: false)
                bumped << max_p
                created << CatchPlacement.create!(
                  catch: @catch, tournament: tournament, tournament_entry: entry,
                  species: @catch.species, slot_index: max_p.slot_index, active: true
                )
                affected_tournaments << tournament
              elsif @catch.length_inches < min_p.catch.length_inches
                min_p.update!(active: false)
                bumped << min_p
                created << CatchPlacement.create!(
                  catch: @catch, tournament: tournament, tournament_entry: entry,
                  species: @catch.species, slot_index: min_p.slot_index, active: true
                )
                affected_tournaments << tournament
              else
                # Catch length is in [min, max] — no placement, no bump.
              end
            end
          elsif tournament.format_fish_train?
            # Fish Train: the train is a sequence of *groups* of consecutive
            # same-species cars. e.g. train [P, W, K, W, W] = 4 groups —
            # {P:1}, {W:1}, {K:1}, {W:2}. Within a group the slots behave like
            # Standard top-N: catches fill empty slots, then the smallest in
            # the group is replaced once it's full. Lock fires at GROUP
            # boundaries, not slot boundaries — catching the next group's
            # species advances and permanently locks the previous group.
            #
            # When a new catch bumps the smallest in a full group, the
            # surviving placements shift to the lower slots (in catch order,
            # oldest first) and the new catch lands in the highest slot of
            # the group. "Fill forward" — newest fish at the highest slot.
            #
            # Judge DQ semantics: deactivating a placement in a past group
            # leaves a permanent hole — a later same-species catch is neither
            # the current group's species nor the next group's species, so it
            # no-ops. A DQ in the *current* group is implicitly re-fillable
            # because group_placements is recomputed on each new catch. This
            # matches BvS: the state machine is append-only; the angler
            # recovers by catching forward, not back.
            all_active = entry.catch_placements
              .where(active: true)
              .includes(:catch).order(:slot_index).to_a
            train = tournament.train_cars
            groups = []
            train.each_with_index do |sp_id, idx|
              if groups.last && groups.last[:species_id] == sp_id
                groups.last[:slot_indices] << idx
              else
                groups << { species_id: sp_id, slot_indices: [idx] }
              end
            end

            current_group_idx = if all_active.empty?
              -1
            else
              groups.index { |g| g[:slot_indices].include?(all_active.last.slot_index) }
            end
            current_group = current_group_idx >= 0 ? groups[current_group_idx] : nil
            next_group    = groups[(current_group_idx >= 0 ? current_group_idx : -1) + 1]

            if current_group && @catch.species_id == current_group[:species_id]
              # Same-species as current group — fill empty slot or replace smallest.
              group_slots = current_group[:slot_indices]
              group_placements = all_active.select { |p| group_slots.include?(p.slot_index) }
              if group_placements.size < group_slots.size
                empty_slot = (group_slots - group_placements.map(&:slot_index)).min
                created << CatchPlacement.create!(
                  catch: @catch, tournament: tournament, tournament_entry: entry,
                  species: @catch.species, slot_index: empty_slot, active: true
                )
                affected_tournaments << tournament
              else
                smallest = group_placements.min_by { |p| p.catch.length_inches }
                if @catch.length_inches > smallest.catch.length_inches
                  smallest.update!(active: false)
                  bumped << smallest
                  survivors = (group_placements - [smallest]).sort_by(&:created_at)
                  # Two-pass shift via unique negative sentinels so survivors
                  # can cross paths (e.g. a 3-car group where the smallest is
                  # in the middle and an older survivor must move past a
                  # newer one). The idx_active_placements_uniq_per_slot index
                  # would reject the intermediate state of a single-pass shift.
                  moves = []
                  survivors.each_with_index do |sp, i|
                    target = group_slots[i]
                    next if sp.slot_index == target
                    moves << [sp, target]
                    sp.update!(slot_index: -(sp.id + 1))
                  end
                  moves.each { |sp, target| sp.update!(slot_index: target) }
                  created << CatchPlacement.create!(
                    catch: @catch, tournament: tournament, tournament_entry: entry,
                    species: @catch.species, slot_index: group_slots.last, active: true
                  )
                  affected_tournaments << tournament
                end
                # else: catch ≤ smallest, no-op
              end
            elsif next_group && @catch.species_id == next_group[:species_id]
              # Advance to next group — fill its first slot.
              created << CatchPlacement.create!(
                catch: @catch, tournament: tournament, tournament_entry: entry,
                species: @catch.species, slot_index: next_group[:slot_indices].first, active: true
              )
              affected_tournaments << tournament
            end
            # else: off-train species, locked-previous-group species, or
            # skip-ahead — no-op
          elsif active_placements.size < slot.slot_count
            next_index = (0...slot.slot_count).find { |i| active_placements.none? { |p| p.slot_index == i } }
            created << CatchPlacement.create!(
              catch: @catch, tournament: tournament, tournament_entry: entry,
              species: @catch.species, slot_index: next_index, active: true
            )
            affected_tournaments << tournament
          else
            smallest = active_placements.min_by { |p| p.catch.length_inches }
            if @catch.length_inches > smallest.catch.length_inches
              smallest.update!(active: false)
              bumped << smallest
              created << CatchPlacement.create!(
                catch: @catch, tournament: tournament, tournament_entry: entry,
                species: @catch.species, slot_index: smallest.slot_index, active: true
              )
              affected_tournaments << tournament
            end
          end
        end
      end

      # Broadcasts and job enqueues happen AFTER our transaction commits so other
      # DB connections (and Solid Queue workers) see the new state when they
      # rebuild the leaderboard or process push notifications.
      #
      # When `broadcast: false`, the caller is running us inside its own outer
      # transaction (which would still be open here, so a broadcast now would
      # leak pre-commit state to other DB connections) and will issue its own
      # broadcast after its outer transaction commits. We skip both the leaderboard
      # rebroadcast and the notification dispatch in that case.
      result = { created: created, bumped: bumped, affected_tournaments: affected_tournaments.to_a, submitter: @catch.user }

      if @broadcast
        affected_tournaments.each { |t| Placements::BroadcastLeaderboard.call(tournament: t) }

        Placements::DetectNotifications.call(result: result).each do |n|
          DeliverPushNotificationJob.perform_later(
            user_id: n[:user].id,
            title: n[:title],
            body: n[:body],
            url: n[:url],
            tournament_id: n[:tournament].id
          )
        end
      end

      result
    end

    private

    def skip_for_out_of_province?
      return false if @catch.latitude.nil?
      !::Geofence.includes?(:sask, @catch.latitude, @catch.longitude)
    end

    def skip_for_local_out_of_bounds?(tournament)
      return false unless tournament.local?
      return false if @catch.latitude.nil?
      !::Geofence.includes?(:lake, @catch.latitude, @catch.longitude)
    end
  end
end
