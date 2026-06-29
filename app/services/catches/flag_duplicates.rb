module Catches
  class FlagDuplicates
    def self.call(catch:)
      return unless catch.persisted? && catch.user_id && catch.captured_at_device
      window = (catch.captured_at_device - ComputeFlags::DUPLICATE_WINDOW)..(catch.captured_at_device + ComputeFlags::DUPLICATE_WINDOW)
      user_ids = ComputeFlags.teammate_user_ids(catch.user_id, at: catch.captured_at_device)
      neighbors = ::Catch.where(user_id: user_ids, captured_at_device: window).where.not(id: catch.id)
      neighbors.find_each do |neighbor|
        next if neighbor.flags.include?("possible_duplicate")
        neighbor.add_flag!("possible_duplicate", bump_to_review: true)
      end
    end
  end
end
