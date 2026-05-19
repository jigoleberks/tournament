# Stable "what code is running right now" identifier, baked into things that
# need to invalidate per deploy (currently: the service worker cache key).
# Prefers ENV["APP_VERSION"], then falls back to the working tree's git SHA,
# then to the process start time so we never crash the SW response on a
# missing .git directory.
module AppVersion
  def self.current
    @current ||= compute
  end

  def self.compute
    return ENV["APP_VERSION"] if ENV["APP_VERSION"].present?

    head_file = Rails.root.join(".git/HEAD")
    return Time.current.to_i.to_s unless head_file.exist?

    head = head_file.read.strip
    if head.start_with?("ref: ")
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
    else
      return head[0, 12]
    end

    Time.current.to_i.to_s
  rescue StandardError
    Time.current.to_i.to_s
  end
end
