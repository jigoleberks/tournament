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
        return { created: [], bumped: [], affected_tournaments: [] } if @catch.disqualified?

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

          if active_placements.size < slot.slot_count
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
      result = { created: created, bumped: bumped, affected_tournaments: affected_tournaments.to_a }

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
