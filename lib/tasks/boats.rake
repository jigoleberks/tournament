namespace :boats do
  desc "Print proposed boats and captains for a club (CLUB_ID=1). Writes nothing."
  task seed_preview: :environment do
    club = Club.find(ENV.fetch("CLUB_ID"))
    rows = Boats::SeedFromHistory.call(club: club, dry_run: true)
    puts format("%-28s %-22s %-16s %-7s %s", "BOAT", "PROPOSED CAPTAIN", "SIGNAL", "NIGHTS", "STATUS")
    rows.each do |row|
      status =
        if row[:captain].nil?
          "—"
        elsif row[:errors].present?
          "BLOCKED: #{row[:errors].join('; ')}"
        else
          "ok"
        end
      puts format("%-28s %-22s %-16s %-7d %s",
                  row[:name], row[:captain]&.name || "— pick one —", row[:signal], row[:nights], status)
    end
    unpicked = rows.count { |r| r[:captain].nil? }
    blocked = rows.count { |r| r[:captain] && r[:errors].present? }
    puts "\n#{unpicked} boat(s) need a captain picked by hand."
    if blocked.positive?
      puts "#{blocked} boat(s) have a captain but would fail to save (see STATUS) — " \
           "a real run rolls back entirely if any of these are still present."
    end
  end

  desc "Create boats from entry history for a club (CLUB_ID=1). Writes."
  task seed: :environment do
    club = Club.find(ENV.fetch("CLUB_ID"))
    rows = Boats::SeedFromHistory.call(club: club, dry_run: false)
    attempted = rows.select { |r| r[:captain] }
    created = rows.select { |r| r[:boat] }

    if created.size < attempted.size
      failed = rows.find { |r| r[:errors].present? }
      reason = failed ? " Blocked on: #{failed[:name]} (#{failed[:errors].join('; ')})" : ""
      puts "Nothing written — the batch rolled back.#{reason}"
    else
      puts "Created #{created.size} boat(s); #{rows.size - created.size} left for a manual pick."
    end
  end
end
