namespace :catches do
  desc "Backfill weather conditions for catches that have GPS but no conditions data"
  task backfill_conditions: :environment do
    scope = Catch.where(moon_phase: nil).where.not(latitude: nil)
    total = scope.count
    puts "Enqueueing conditions fetch for #{total} catches…"
    scope.ids.each { |id| FetchCatchConditionsJob.perform_later(catch_id: id) }
    puts "Done. Jobs queued — check Solid Queue for progress."
  end
end
