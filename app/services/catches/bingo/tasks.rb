module Catches
  module Bingo
    # Fixed catalog of the 24 bingo tasks. Each task is data + a `completed_at`
    # predicate: given the engine's evaluation context, it returns the earliest
    # Time the task is satisfied, or nil. Order here is irrelevant — layout
    # positions are randomized per tournament.
    module Tasks
      FREE_INDEX = 12

      module Builders
        module_function

        # The Nth chronological catch of a species (catches arrive sorted asc).
        def nth_species(sym, n)
          ->(ctx) do
            sp = ctx.species_id(sym)
            return nil unless sp
            matches = ctx.catches.select { |c| c.species_id == sp }
            matches.size >= n ? matches[n - 1].at : nil
          end
        end

        # Earliest any-species catch whose length is within [lo, hi].
        def length_band(lo, hi)
          ->(ctx) { ctx.catches.find { |c| c.length >= lo && c.length <= hi }&.at }
        end

        # Earliest catch of a species matching optional bounds. Pass exactly the
        # bounds a task needs: :lo/:hi inclusive, :gt/:lt strict.
        def species_length(sym, lo: nil, hi: nil, gt: nil, lt: nil)
          ->(ctx) do
            sp = ctx.species_id(sym)
            return nil unless sp
            ctx.catches.find do |c|
              next false unless c.species_id == sp
              (lo.nil? || c.length >= lo) && (hi.nil? || c.length <= hi) &&
                (gt.nil? || c.length > gt) && (lt.nil? || c.length < lt)
            end&.at
          end
        end

        # Earliest catch whose local wall-clock hour equals `hour` (0-23).
        def time_window(hour)
          ->(ctx) { ctx.catches.find { |c| ctx.local_hour(c.at) == hour }&.at }
        end

        # Earliest 2nd-of-a-pair time where two catches are <= 10 min apart.
        # Sorted asc, the closest earlier neighbor is adjacent, so scanning
        # adjacent pairs finds the earliest qualifying completion.
        def two_within(seconds)
          ->(ctx) do
            ctx.catches.each_cons(2) { |a, b| return b.at if (b.at - a.at) <= seconds }
            nil
          end
        end

        # Completes when the (n+1)th catch lands ("over n fish").
        def over_count(n)
          ->(ctx) { ctx.catches.size > n ? ctx.catches[n].at : nil }
        end
      end

      B = Builders

      ALL = [
        { key: "walleye_1", label: "Catch a Walleye",          completed_at: B.nth_species(:walleye, 1) },
        { key: "walleye_2", label: "Catch a second Walleye",   completed_at: B.nth_species(:walleye, 2) },
        { key: "walleye_3", label: "Catch a third Walleye",    completed_at: B.nth_species(:walleye, 3) },
        { key: "perch_1",   label: "Catch a Perch",            completed_at: B.nth_species(:perch, 1) },
        { key: "perch_2",   label: "Catch a second Perch",     completed_at: B.nth_species(:perch, 2) },
        { key: "pike_1",    label: "Catch a Pike",             completed_at: B.nth_species(:pike, 1) },
        { key: "pike_2",    label: "Catch a second Pike",      completed_at: B.nth_species(:pike, 2) },

        { key: "len_5_1175",    label: %(Catch a fish 5"-11.75"),     completed_at: B.length_band(5.0, 11.75) },
        { key: "len_1225_1475", label: %(Catch a fish 12.25"-14.75"), completed_at: B.length_band(12.25, 14.75) },
        { key: "len_1525_1775", label: %(Catch a fish 15.25"-17.75"), completed_at: B.length_band(15.25, 17.75) },
        { key: "len_1825_2075", label: %(Catch a fish 18.25"-20.75"), completed_at: B.length_band(18.25, 20.75) },
        { key: "len_2125_30",   label: %(Catch a fish 21.25"-30"),    completed_at: B.length_band(21.25, 30.0) },

        { key: "time_hour1", label: "Catch a fish 6:00-6:59 PM", completed_at: B.time_window(18) },
        { key: "time_hour2", label: "Catch a fish 7:00-7:59 PM", completed_at: B.time_window(19) },
        { key: "time_hour3", label: "Catch a fish 8:00-8:59 PM", completed_at: B.time_window(20) },

        { key: "walleye_lt125",  label: %(Walleye below 12.5"),  completed_at: B.species_length(:walleye, lt: 12.5) },
        { key: "walleye_13_185", label: %(Walleye 13"-18.5"),    completed_at: B.species_length(:walleye, lo: 13.0, hi: 18.5) },
        { key: "walleye_gt19",   label: %(Walleye above 19"),    completed_at: B.species_length(:walleye, gt: 19.0) },
        { key: "pike_lt24",      label: %(Pike below 24"),       completed_at: B.species_length(:pike, lt: 24.0) },
        { key: "pike_gt245",     label: %(Pike above 24.5"),     completed_at: B.species_length(:pike, gt: 24.5) },
        { key: "perch_lt11",     label: %(Perch below 11"),      completed_at: B.species_length(:perch, lt: 11.0) },
        { key: "perch_gt115",    label: %(Perch above 11.5"),    completed_at: B.species_length(:perch, gt: 11.5) },

        { key: "two_within_10min", label: "Catch 2 fish within 10 min", completed_at: B.two_within(10 * 60) },
        { key: "over_10_fish",     label: "Catch over 10 fish",         completed_at: B.over_count(10) },
      ].freeze

      BY_KEY = ALL.index_by { |t| t[:key] }.freeze

      def self.fetch(key) = BY_KEY.fetch(key)
      def self.keys = ALL.map { |t| t[:key] }

      # A fresh randomized 25-cell layout: the 24 keys shuffled, with "free" at
      # the center. Called at tournament creation and on re-shuffle.
      def self.random_layout
        cells = keys.shuffle
        cells.insert(FREE_INDEX, "free")
        cells
      end
    end
  end
end
