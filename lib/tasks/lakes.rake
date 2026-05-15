namespace :lakes do
  desc "Compute and store the lake key for every catch with GPS coordinates"
  task backfill: :environment do
    scope = Catch.where.not(latitude: nil, longitude: nil)
    total = scope.count
    updated = 0
    scope.find_each(batch_size: 500) do |c|
      key = Catches::DetectLake.call(c)
      next if c.lake == key
      c.update_columns(lake: key)
      updated += 1
    end
    puts "Backfill complete: #{updated}/#{total} catches updated"
  end
end
