module Catches
  class ComputeFlags
    CLOCK_SKEW_THRESHOLD = 5.minutes
    DUPLICATE_WINDOW = 90.seconds

    # Flags computed from catch state by .call. Any flag on a catch that is NOT
    # in this set was written out-of-band (e.g. imported_photo by
    # FlagImportedPhotoJob) and must survive a recompute — see .recompute.
    OWNED_FLAGS = %w[missing_gps clock_skew out_of_bounds out_of_province possible_duplicate].freeze

    def self.call(catch_record)
      flags = []
      flags << "missing_gps" if catch_record.latitude.nil?
      if catch_record.captured_at_device && catch_record.captured_at_gps
        skew = (catch_record.captured_at_device - catch_record.captured_at_gps).abs
        flags << "clock_skew" if skew > CLOCK_SKEW_THRESHOLD
      end
      if catch_record.latitude.present? && !catch_record.in_geofence?(:lake)
        flags << "out_of_bounds"
      end
      if catch_record.latitude.present? && !catch_record.in_geofence?(:sask)
        flags << "out_of_province"
      end
      flags << "possible_duplicate" if duplicate_neighbor?(catch_record)
      flags
    end

    # Re-derive owned flags from current state while preserving any out-of-band
    # flags already on the catch, so a recompute (e.g. after a geofence/location
    # correction) never silently drops a flag ComputeFlags doesn't own.
    def self.recompute(catch_record)
      external = catch_record.flags - OWNED_FLAGS
      (call(catch_record) + external).uniq
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
