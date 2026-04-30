namespace :storage do
  desc "Delete files in storage/ that have no matching active_storage_blobs row"
  task cleanup_orphans: :environment do
    require "set"

    storage_root = Rails.root.join("storage")
    blob_keys = Set.new(ActiveStorage::Blob.pluck(:key))

    deleted = 0
    freed_bytes = 0

    Dir.glob(storage_root.join("**", "*")).each do |path|
      next if File.directory?(path)
      next if File.basename(path) == ".keep"
      next if blob_keys.include?(File.basename(path))
      size = File.size(path)
      File.delete(path)
      deleted += 1
      freed_bytes += size
    end

    Dir.glob(storage_root.join("*", "*")).each { |d| Dir.rmdir(d) if File.directory?(d) && Dir.empty?(d) }
    Dir.glob(storage_root.join("*")).each       { |d| Dir.rmdir(d) if File.directory?(d) && Dir.empty?(d) }

    puts "[#{Time.current.iso8601}] storage:cleanup_orphans — deleted #{deleted} files, #{(freed_bytes / 1024.0 / 1024.0).round(2)} MB freed."
  end
end
