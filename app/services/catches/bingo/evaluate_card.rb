module Catches
  module Bingo
    # Derives an entry's bingo card purely from its in-window, non-DQ'd catches.
    # No stored fill-state; called on every leaderboard/card build & broadcast.
    class EvaluateCard
      # The 12 winning lines by grid index: 5 rows, 5 cols, 2 diagonals.
      LINES = [
        [0, 1, 2, 3, 4], [5, 6, 7, 8, 9], [10, 11, 12, 13, 14], [15, 16, 17, 18, 19], [20, 21, 22, 23, 24],
        [0, 5, 10, 15, 20], [1, 6, 11, 16, 21], [2, 7, 12, 17, 22], [3, 8, 13, 18, 23], [4, 9, 14, 19, 24],
        [0, 6, 12, 18, 24], [4, 8, 12, 16, 20]
      ].freeze

      CatchLite = Struct.new(:id, :length, :species_id, :at, keyword_init: true)

      Result = Struct.new(:cells, :squares_count, :square_times, :lines_count,
                          :line_times, :blackout, :blackout_at, keyword_init: true)

      # Evaluation context handed to each task predicate.
      class Context
        def initialize(catches:, species_ids:, time_zone:)
          @catches = catches
          @species_ids = species_ids
          @time_zone = time_zone
        end

        attr_reader :catches

        def species_id(sym) = @species_ids[sym]

        # `at` already denotes the correct instant: read from the DB, captured_at_device
        # is a time-zone-aware ActiveSupport::TimeWithZone; the unit tests pass a raw
        # UTC Time. Either way, presenting it in the tournament's local zone gives the
        # wall-clock hour. (An earlier version rebuilt the components as if they were
        # UTC and re-converted, which double-applied the offset whenever the app zone
        # wasn't UTC — e.g. APP_TIME_ZONE=Saskatchewan bucketed a 6:30 PM catch to noon.)
        def local_hour(at)
          at.in_time_zone(@time_zone).hour
        end
      end

      def self.call(...) = new(...).call

      # The walleye/perch/pike ids are the same for every entry in a tournament.
      # Resolve them once and inject via species_ids: when evaluating many cards
      # in a loop (see Leaderboards::Build.bingo_rows) to avoid re-querying Species
      # per entry.
      def self.species_id_map
        names = { walleye: ::Species::WALLEYE_NAME, perch: ::Species::PERCH_NAME, pike: ::Species::PIKE_NAME }
        # One round-trip for all three; names are globally unique (case-insensitive).
        by_lower = ::Species
          .where("lower(name) IN (?)", names.values.map(&:downcase))
          .pluck(:name, :id)
          .to_h { |name, id| [name.downcase, id] }
        names.transform_values { |canonical| by_lower[canonical.downcase] }
      end

      def initialize(tournament:, entry:, catches: nil, species_ids: nil, time_zone: Time.zone)
        @tournament = tournament
        @entry = entry
        @catches = catches
        @species_ids = species_ids
        @time_zone = time_zone
      end

      def call
        cats = (@catches || load_catches).sort_by(&:at)
        ctx = Context.new(catches: cats, species_ids: species_ids, time_zone: @time_zone)

        cells = @tournament.bingo_layout.each_with_index.map do |key, index|
          if key == "free"
            { index: index, key: "free", label: "Show up to League Night",
              filled: true, completed_at: @tournament.starts_at }
          else
            task = Tasks.fetch(key)
            at = task[:completed_at].call(ctx)
            { index: index, key: key, label: task[:label], filled: !at.nil?, completed_at: at }
          end
        end

        filled = cells.select { |c| c[:filled] }
        square_times = filled.map { |c| c[:completed_at] }.sort
        line_times = LINES.filter_map do |idxs|
          times = idxs.map { |i| cells[i][:completed_at] }
          times.max if times.all?
        end.sort
        blackout = filled.size == 25

        Result.new(
          cells: cells,
          squares_count: filled.size,
          square_times: square_times,
          lines_count: line_times.size,
          line_times: line_times,
          blackout: blackout,
          blackout_at: (blackout ? square_times.max : nil)
        )
      end

      private

      def load_catches
        user_ids = @entry.users.pluck(:id)
        ::Catch.where(user_id: user_ids)
          .where.not(status: :disqualified)
          .where(captured_at_device: @tournament.starts_at..@tournament.ends_at)
          .reject { |c| excluded_by_geofence?(c) }
          .map { |c| CatchLite.new(id: c.id, length: c.length_inches, species_id: c.species_id, at: c.captured_at_device) }
      end

      # Mirror PlaceInSlots' hard scoring exclusions (skip_for_out_of_province? /
      # skip_for_local_out_of_bounds?) so a bingo card scores the same catches every
      # other format does: an out-of-province catch never counts, and on a local
      # tournament a catch outside the lake never counts. A GPS-less catch is kept,
      # and judge geofence overrides are honored via Catch#in_geofence?.
      def excluded_by_geofence?(catch)
        return false if catch.latitude.nil?
        return true unless catch.in_geofence?(:sask)
        @tournament.local? && !catch.in_geofence?(:lake)
      end

      def species_ids
        @species_ids ||= self.class.species_id_map
      end
    end
  end
end
