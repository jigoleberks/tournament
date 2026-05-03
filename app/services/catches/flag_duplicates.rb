module Catches
  class FlagDuplicates
    def self.call(catch:)
      return unless catch.persisted? && catch.user_id && catch.captured_at_device
      window = (catch.captured_at_device - ComputeFlags::DUPLICATE_WINDOW)..(catch.captured_at_device + ComputeFlags::DUPLICATE_WINDOW)
      neighbors = ::Catch.where(user_id: catch.user_id, captured_at_device: window).where.not(id: catch.id)
      neighbors.find_each do |neighbor|
        next if neighbor.flags.include?("possible_duplicate")
        new_flags = neighbor.flags + ["possible_duplicate"]
        new_status = neighbor.status == "synced" ? ::Catch.statuses["needs_review"] : ::Catch.statuses[neighbor.status]
        neighbor.update_columns(flags: new_flags, status: new_status)
      end
    end
  end
end
