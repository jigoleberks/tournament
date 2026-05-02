module Catches
  class PlaceInSlots
    def self.call(catch:)
      new(catch: catch).call
    end

    def initialize(catch:)
      @catch = catch
    end

    def call
      created, bumped = [], []
      affected_tournaments = Set.new

      Tournaments::ActiveForUser.with_entries(user: @catch.user, at: @catch.captured_at_device).each do |row|
        tournament = row[:tournament]
        entry      = row[:entry]
        slot       = tournament.scoring_slots.find_by(species_id: @catch.species_id)
        next if slot.nil?
        next if skip_for_local_out_of_bounds?(tournament)

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

      affected_tournaments.each { |t| Placements::BroadcastLeaderboard.call(tournament: t) }

      result = { created: created, bumped: bumped, affected_tournaments: affected_tournaments.to_a }

      Placements::DetectNotifications.call(result: result).each do |n|
        DeliverPushNotificationJob.perform_later(
          user_id: n[:user].id,
          title: n[:title],
          body: n[:body],
          url: n[:url],
          tournament_id: n[:tournament].id
        )
      end

      result
    end

    private

    def skip_for_local_out_of_bounds?(tournament)
      return false unless tournament.local?
      return false if @catch.latitude.nil?
      !Geofence.includes?(@catch.latitude, @catch.longitude)
    end
  end
end
