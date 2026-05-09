namespace :catches do
  desc "Backfill weather conditions for catches that have GPS but no conditions data"
  task backfill_conditions: :environment do
    scope = Catch.where(moon_phase: nil)
    total = scope.count
    puts "Fetching conditions for #{total} catches…"
    scope.ids.each_with_index do |id, i|
      FetchCatchConditionsJob.perform_now(catch_id: id)
      puts "  #{i + 1}/#{total} done"
    end
    puts "Done."
  end

  desc "Backfill wind direction for catches that have GPS but no direction stored"
  task backfill_wind_direction: :environment do
    scope = Catch.where(wind_direction_deg: nil)
               .where.not(latitude: nil, longitude: nil)
    total = scope.count
    puts "Refetching wind direction for #{total} catches…"
    scope.ids.each_with_index do |id, i|
      FetchCatchConditionsJob.perform_now(catch_id: id)
      puts "  #{i + 1}/#{total} done"
    end
    puts "Done."
  end

  desc "Backfill flags for catches whose flag column is empty"
  task backfill_flags: :environment do
    scope = Catch.where("array_length(flags, 1) IS NULL")
    total = scope.count
    updated = 0
    puts "Computing flags for #{total} catches with empty flags…"
    scope.find_each do |c|
      computed = Catches::ComputeFlags.call(c)
      next if computed.empty?
      c.update_columns(flags: computed)
      updated += 1
    end
    puts "Done. Updated #{updated} of #{total}."
  end

  desc "Pre-generate photo variants so the first user-facing load isn't slow"
  task warm_photo_variants: :environment do
    sizes = [[200, 200], [400, 400], [1200, 1200]]
    scope = Catch.joins(:photo_attachment).includes(photo_attachment: :blob)
    total = scope.count
    puts "Warming #{sizes.size} variants × #{total} catches…"
    scope.find_each.with_index do |c, i|
      sizes.each { |size| c.photo.variant(resize_to_limit: size).processed }
      puts "  #{i + 1}/#{total}"
    end
    puts "Done."
  end
end
