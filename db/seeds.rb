# This file should ensure the existence of records required to run the application in every environment (production,
# development, test). The code here should be idempotent so that it can be executed at any point in every environment.
# The data can then be loaded with the bin/rails db:seed command (or created alongside the database with db:setup).
#
# Edit the values below before running `bin/rails db:seed` for the first time, OR set the
# corresponding env vars (SEED_CLUB_NAME, SEED_ORGANIZER_NAME, SEED_ORGANIZER_EMAIL).

club_name = ENV.fetch("SEED_CLUB_NAME", "Example Fishing Club")
org_name  = ENV.fetch("SEED_ORGANIZER_NAME", "Organizer")
org_email = ENV.fetch("SEED_ORGANIZER_EMAIL", "organizer@example.com")

club = Club.find_or_create_by!(name: club_name)
%w[Walleye Perch Pike Other].each { |n| Species.find_or_create_by!(club: club, name: n) }

User.find_or_create_by!(club: club, email: org_email) do |u|
  u.name = org_name
  u.role = :organizer
end

%w[member1 member2 member3].each_with_index do |handle, i|
  User.find_or_create_by!(club: club, email: "#{handle}@example.com") do |u|
    u.name = "Member #{i + 1}"
    u.role = :member
  end
end

walleye = Species.find_by!(club: club, name: "Walleye")
perch   = Species.find_by!(club: club, name: "Perch")

Tournament.find_or_create_by!(club: club, name: "Sample Event Tournament") do |t|
  t.kind = :event
  t.mode = :solo
  t.starts_at = 1.hour.ago
  t.ends_at   = 4.hours.from_now
  t.season_tag = "Open Water 2026"
end.tap do |t|
  t.scoring_slots.find_or_create_by!(species: walleye) { |s| s.slot_count = 2 }
  t.scoring_slots.find_or_create_by!(species: perch)   { |s| s.slot_count = 1 }
end

Tournament.find_or_create_by!(club: club, name: "Sample Ongoing: Biggest Walleye") do |t|
  t.kind = :ongoing
  t.mode = :solo
  t.starts_at = 1.month.ago
  t.ends_at   = nil
  t.season_tag = "Open Water 2026"
end.tap do |t|
  t.scoring_slots.find_or_create_by!(species: walleye) { |s| s.slot_count = 1 }
end
