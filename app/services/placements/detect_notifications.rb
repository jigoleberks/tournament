module Placements
  class DetectNotifications
    def self.call(result:)
      new(result: result).call
    end

    def initialize(result:)
      @result = result
    end

    def call
      payloads = []
      bumped_users.each do |row|
        payloads << {
          user: row[:user],
          reason: "bumped",
          tournament: row[:tournament],
          title: row[:tournament].name,
          body: "You were bumped from a slot.",
          url: "/tournaments/#{row[:tournament].id}"
        }
      end
      lead_changes.each do |row|
        payloads << {
          user: row[:user],
          reason: "took_the_lead",
          tournament: row[:tournament],
          title: row[:tournament].name,
          body: "You took the lead!",
          url: "/tournaments/#{row[:tournament].id}"
        }
      end
      payloads
    end

    private

    def bumped_users
      @result[:bumped].flat_map do |placement|
        placement.tournament_entry.users.map do |user|
          { user: user, tournament: placement.tournament }
        end
      end
    end

    def lead_changes
      @result[:affected_tournaments].flat_map do |t|
        leader_entry = Leaderboards::Build.call(tournament: t).first&.dig(:entry)
        next [] unless leader_entry

        new_leader_users = leader_entry.users
        # Did the leader entry just receive a created placement in this run?
        leader_just_created = @result[:created].any? { |p| p.tournament_entry_id == leader_entry.id && p.tournament_id == t.id }
        next [] unless leader_just_created

        new_leader_users.map { |u| { user: u, tournament: t } }
      end
    end
  end
end
