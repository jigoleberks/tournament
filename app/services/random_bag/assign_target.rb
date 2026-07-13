module RandomBag
  # Lazily assigns a team's random target the first time its entry is viewed while
  # the tournament is active (started, not yet ended), then persists it. Before
  # starts_at the target stays nil (the UI shows a "revealed at start"
  # placeholder). Independent draws per team at 1/4-inch steps; collisions are
  # allowed and rare at that granularity. The outer nil-guard keeps the common
  # already-assigned path lock-free; the with_lock re-check makes the first
  # assignment race-safe.
  class AssignTarget
    STEP = BigDecimal("0.25")

    def self.call(entry:, tournament: nil)
      tournament ||= entry.tournament
      return unless tournament.format_random_bag?
      return unless tournament.started?
      # Already drawn during play — hand it back (including at reveal, so the
      # ended board still shows each team its assigned target).
      return entry.random_bag_target_inches if entry.random_bag_target_inches.present?
      # Don't mint a brand-new target once the event is over: a post-hoc draw is
      # meaningless, and assigning here would put a row-lock + write into the
      # read-only archive/season-standings aggregations (WinnersFor,
      # SeasonPoints::Standings) that build ended boards. A team never viewed
      # while active simply shows no target ("—") at reveal.
      return if tournament.ended?

      entry.with_lock do
        return entry.random_bag_target_inches if entry.random_bag_target_inches.present?
        min = tournament.target_min_inches.to_d
        max = tournament.target_max_inches.to_d
        steps = ((max - min) / STEP).floor
        target = min + STEP * rand(0..steps)
        entry.update!(random_bag_target_inches: target)
        target
      end
    end
  end
end
