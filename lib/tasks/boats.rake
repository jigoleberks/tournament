namespace :boats do
  desc "Print proposed boats and captains for a club (CLUB_ID=1). Writes nothing."
  task seed_preview: :environment do
    club = Club.find(ENV.fetch("CLUB_ID"))
    rows = Boats::SeedFromHistory.call(club: club, dry_run: true)
    puts format("%-28s %-22s %-16s %s", "BOAT", "PROPOSED CAPTAIN", "SIGNAL", "NIGHTS")
    rows.each do |row|
      puts format("%-28s %-22s %-16s %d",
                  row[:name], row[:captain]&.name || "— pick one —", row[:signal], row[:nights])
    end
    puts "\n#{rows.count { |r| r[:captain].nil? }} boat(s) need a captain picked by hand."
  end

  desc "Create boats from entry history for a club (CLUB_ID=1). Writes."
  task seed: :environment do
    club = Club.find(ENV.fetch("CLUB_ID"))
    rows = Boats::SeedFromHistory.call(club: club, dry_run: false)
    created = rows.count { |r| r[:boat] }
    puts "Created #{created} boat(s); #{rows.size - created} left for a manual pick."
  end
end
