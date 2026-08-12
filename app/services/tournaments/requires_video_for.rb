module Tournaments
  # Does this angler owe a release video for any tournament active at `at`?
  # The ONE spelling of the check: the catch form uses it to decide whether to
  # render the video recorder, and Catches::ComputeFlags uses it to stamp
  # video_missing. Keeping a private copy in either place invites drift —
  # anglers flagged with no recorder offered, or a recorder shown that no
  # tournament requires.
  class RequiresVideoFor
    def self.call(user:, at: Time.current)
      # No tournament anywhere requires video (the usual case) → skip the
      # per-user active-tournament lookup, which costs two queries per call.
      return false unless ::Tournament.where(requires_release_video: true).exists?
      ActiveForUser.call(user: user, at: at).any?(&:requires_release_video)
    end
  end
end
