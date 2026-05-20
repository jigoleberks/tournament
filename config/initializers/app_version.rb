# Identifier for "what code is running right now", baked into things that need
# to invalidate per deploy (currently: the service worker cache key).
#
# Re-resolved on every call rather than memoized: a deploy changes the
# checked-out git SHA but does not necessarily restart the Puma process --
# bin/update runs `docker compose up -d`, which is a no-op for the already
# running, volume-mounted `web` container -- so a process-lifetime memo would
# keep serving the pre-deploy cache key until the next manual restart.
#
# Prefers ENV["APP_VERSION"], then the working tree's git SHA, then a
# process-stable fallback so the SW response never crashes on a missing .git.
module AppVersion
  def self.current
    ENV["APP_VERSION"].presence || git_sha || boot_fallback
  end

  # The first 12 chars of the checked-out commit SHA, or nil if it can't be
  # resolved from the .git directory.
  def self.git_sha
    head_file = Rails.root.join(".git/HEAD")
    return nil unless head_file.exist?

    head = head_file.read.strip
    return head[0, 12] unless head.start_with?("ref: ")

    ref_name = head.sub("ref: ", "")
    loose = Rails.root.join(".git", ref_name)
    return loose.read.strip[0, 12] if loose.exist?

    packed = Rails.root.join(".git/packed-refs")
    if packed.exist?
      packed.each_line do |line|
        parts = line.split
        return parts.first[0, 12] if parts.size == 2 && parts.last == ref_name
      end
    end

    nil
  rescue StandardError
    nil
  end

  # Last resort when there is no APP_VERSION and no .git directory (e.g. a
  # baked image that .dockerignores .git). Memoized so it stays fixed for the
  # life of the process -- it has nothing to re-resolve, and recomputing it
  # would churn the SW cache key on every request.
  def self.boot_fallback
    @boot_fallback ||= Time.current.to_i.to_s
  end
end
