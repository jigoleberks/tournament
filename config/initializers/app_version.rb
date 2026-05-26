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
  # Computed once at module load so every request in this process returns the
  # same value. Under Puma's default single-mode (no `workers` directive in
  # config/puma.rb) there's one process, so this is stable across requests.
  # If a future deploy enables WEB_CONCURRENCY > 1, also enable preload_app!
  # in puma.rb so workers inherit this constant from the master, otherwise
  # each worker computes a different timestamp and the SW cache key thrashes.
  BOOT_FALLBACK = Time.current.to_i.to_s

  def self.current
    ENV["APP_VERSION"].presence || git_sha || BOOT_FALLBACK
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

  # Public accessor for the boot fallback. Kept for the test suite, which
  # verifies the value stays fixed for the life of the process.
  def self.boot_fallback
    BOOT_FALLBACK
  end
end
