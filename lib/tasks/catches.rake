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
end
