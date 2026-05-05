module Catches
  class ComputeFlags
    CLOCK_SKEW_THRESHOLD = 5.minutes
    DUPLICATE_WINDOW = 90.seconds

    def self.call(catch_record)
      flags = []
      flags << "missing_gps" if catch_record.latitude.nil?
      if catch_record.captured_at_device && catch_record.captured_at_gps
        skew = (catch_record.captured_at_device - catch_record.captured_at_gps).abs
        flags << "clock_skew" if skew > CLOCK_SKEW_THRESHOLD
      end
      if catch_record.latitude.present? && !::Geofence.includes?(:lake, catch_record.latitude, catch_record.longitude)
        flags << "out_of_bounds"
      end
      if catch_record.latitude.present? && !::Geofence.includes?(:sask, catch_record.latitude, catch_record.longitude)
        flags << "out_of_province"
      end
      flags << "possible_duplicate" if duplicate_neighbor?(catch_record)
      flags
    end

    def self.duplicate_neighbor?(catch_record)
      return false if catch_record.user_id.nil? || catch_record.captured_at_device.nil?
      window = (catch_record.captured_at_device - DUPLICATE_WINDOW)..(catch_record.captured_at_device + DUPLICATE_WINDOW)
      scope = ::Catch.where(user_id: teammate_user_ids(catch_record.user_id, at: catch_record.captured_at_device),
                            captured_at_device: window)
      scope = scope.where.not(id: catch_record.id) if catch_record.id
      scope.exists?
    end

    # User ids that share at least one tournament entry with `user_id` in a
    # tournament active at `at` (always includes the user themselves). Used to
    # flag fish-passing within a team: two members of the same entry both
    # submitting catches within the dup window get flagged as possible_duplicate
    # for judge review. Teams reform every tournament — whoever's in the boat —
    # so we scope to tournaments live at the catch's timestamp.
    def self.teammate_user_ids(user_id, at:)
      shared_entry_ids = TournamentEntryMember
        .joins(tournament_entry: :tournament)
        .where(user_id: user_id)
        .where("tournaments.starts_at <= ? AND (tournaments.ends_at IS NULL OR tournaments.ends_at >= ?)", at, at)
        .pluck(:tournament_entry_id)
      return [ user_id ] if shared_entry_ids.empty?
      TournamentEntryMember.where(tournament_entry_id: shared_entry_ids).pluck(:user_id).uniq
    end
  end
end
