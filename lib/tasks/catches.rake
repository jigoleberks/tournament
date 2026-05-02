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
end
