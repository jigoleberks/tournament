module Leaderboards
  class PresentationOrder
    # Reorders ranked leaderboard rows for display so row position does not leak
    # placement during a blind tournament.
    #
    # - :full           -> caller's order is preserved (rank for live, reveal, judges).
    # - :own_entry_only -> viewer's entry first, remaining entries case-insensitive
    #                     alphabetical by display_name (entry.id ascending tiebreaker).
    # - :entries_only   -> all entries case-insensitive alphabetical by display_name.
    def self.call(rows:, viewer_scope:)
      case viewer_scope.visibility
      when :own_entry_only
        own, others = rows.partition { |r| r[:entry].id == viewer_scope.entry_id }
        own + alphabetical(others)
      when :entries_only
        alphabetical(rows)
      else
        rows
      end
    end

    def self.alphabetical(rows)
      rows.sort_by { |r| [r[:entry].display_name.downcase, r[:entry].id] }
    end
  end
end
