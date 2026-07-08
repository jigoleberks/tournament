module Placements
  class DetectNotifications
    def self.call(result:, leaderboards: {})
      new(result: result, leaderboards: leaderboards).call
    end

    # `leaderboards` is an optional { tournament_id => built_leaderboard } cache
    # so callers that already built a tournament's leaderboard (e.g. PlaceInSlots
    # for its broadcast) don't pay to rebuild it here. Missing ids fall back to
    # an on-demand build.
    def initialize(result:, leaderboards: {})
      @result = result
      @leaderboards = leaderboards
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
      (lead_changes + bingo_lead_changes).each do |row|
        payloads << {
          user: row[:user],
          reason: "took_the_lead",
          tournament: row[:tournament],
          title: row[:tournament].name,
          body: "You took the lead!",
          url: "/tournaments/#{row[:tournament].id}"
        }
      end
      payloads.reject { |p| p[:tournament].blind?(at: Time.current) }
    end

    private

    def bumped_users
      submitter = @result[:submitter]
      @result[:bumped].flat_map do |placement|
        placement.tournament_entry.users.reject { |u| u == submitter }.map do |user|
          { user: user, tournament: placement.tournament }
        end
      end
    end

    def lead_changes
      @result[:affected_tournaments].flat_map do |t|
        # Hidden Length pre-reveal: leaderboard is sorted by length, but length
        # isn't the winning metric, so a "took the lead" push would mislead.
        next [] if t.format_hidden_length? && t.hidden_length_target.nil?

        leaderboard = @leaderboards[t.id] || Leaderboards::Build.call(tournament: t)
        leader_entry = leaderboard.first&.dig(:entry)
        next [] unless leader_entry

        new_leader_users = leader_entry.users
        # Did the leader entry just receive a created placement in this run?
        leader_just_created = @result[:created].any? { |p| p.tournament_entry_id == leader_entry.id && p.tournament_id == t.id }
        next [] unless leader_just_created

        new_leader_users.map { |u| { user: u, tournament: t } }
      end
    end

    # Bingo lead changes are precomputed by PlaceInSlots (it holds the catch needed
    # to tell whether a square was newly stamped) and handed over as
    # result[:bingo_lead] = [{ tournament:, entry: }]. Expand to one row per angler.
    def bingo_lead_changes
      (@result[:bingo_lead] || []).flat_map do |row|
        row[:entry].users.map { |u| { user: u, tournament: row[:tournament] } }
      end
    end
  end
end
