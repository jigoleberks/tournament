# This file should ensure the existence of records required to run the application in every environment (production,
# development, test). The code here should be idempotent so that it can be executed at any point in every environment.
# The data can then be loaded with the bin/rails db:seed command (or created alongside the database with db:setup).
#
# Edit the values below before running `bin/rails db:seed` for the first time, OR set the
# corresponding env vars (SEED_CLUB_NAME, SEED_ORGANIZER_NAME, SEED_ORGANIZER_EMAIL).
# Set SEED_DEMO_DATA=true to also create stub members and sample tournaments (off by default).

club_name = ENV.fetch("SEED_CLUB_NAME", "Example Fishing Club")
org_name  = ENV.fetch("SEED_ORGANIZER_NAME", "Organizer")
org_email = ENV.fetch("SEED_ORGANIZER_EMAIL", "organizer@example.com")

club = Club.find_or_create_by!(name: club_name)
["Walleye", "Perch", "Pike", "Stocked Trout", "Lake Trout", "Bass", "Tagged Walleye", "Other"].each do |n|
  Species.find_or_create_by!(name: n)
end

organizer = User.find_or_create_by!(email: org_email) { |u| u.name = org_name }
ClubMembership.find_or_create_by!(user: organizer, club: club) { |m| m.role = :organizer }

# Demo members and sample tournaments are only created when SEED_DEMO_DATA=true.
# Without this guard, db:seed silently re-creates them in real clubs on every run.
if ENV["SEED_DEMO_DATA"] == "true"
  %w[member1 member2 member3].each_with_index do |handle, i|
    user = User.find_or_create_by!(email: "#{handle}@example.com") { |u| u.name = "Member #{i + 1}" }
    ClubMembership.find_or_create_by!(user: user, club: club) { |m| m.role = :member }
  end

  walleye = Species.find_by!(name: "Walleye")
  perch   = Species.find_by!(name: "Perch")

  Tournament.find_or_create_by!(club: club, name: "Sample Event Tournament") do |t|
    t.mode = :solo
    t.starts_at = 1.hour.ago
    t.ends_at   = 4.hours.from_now
    t.season_tag = "Open Water 2026"
  end.tap do |t|
    t.scoring_slots.find_or_create_by!(species: walleye) { |s| s.slot_count = 2 }
    t.scoring_slots.find_or_create_by!(species: perch)   { |s| s.slot_count = 1 }
  end

  Tournament.find_or_create_by!(club: club, name: "Sample Season: Biggest Walleye") do |t|
    t.mode = :solo
    t.starts_at = 1.month.ago
    t.ends_at   = 5.months.from_now
    t.season_tag = "Open Water 2026"
  end.tap do |t|
    t.scoring_slots.find_or_create_by!(species: walleye) { |s| s.slot_count = 1 }
  end
end

# Boats + a linked league-night pair, for hands-on testing of the boat entry
# flow on a phone. Development-only; additive against the developer's working
# database (a brand-new "Test Anglers" club, never touching existing clubs).
if Rails.env.development?
  club = Club.find_or_create_by!(name: "Test Anglers")
  captains = {
    "Majestic Red" => "Kurtis Sanguin",
    "Team Patterson" => "Galen Patterson",
    "Team Willow River" => "Curtis Johnston",
    "Big Tiller" => "Kent Pierce",
    "The Pearl" => "Jeremy Laroo",
    "Team Loos" => "Tyson Loos"
  }
  captains.each_value do |name|
    user = User.find_or_create_by!(email: "#{name.parameterize}@example.com") { |u| u.name = name }
    club.club_memberships.find_or_create_by!(user: user) { |m| m.role = :member }
  end
  captains.each do |boat_name, captain_name|
    captain = User.find_by!(email: "#{captain_name.parameterize}@example.com")
    club.boats.find_or_create_by!(name: boat_name) { |b| b.captain = captain }
  end

  group = SecureRandom.uuid
  starts_at = Date.current.next_occurring(:wednesday).in_time_zone + 18.hours
  ["Wednesday League Night - Main", "Wednesday League Night - Side"].each do |name|
    club.tournaments.find_or_create_by!(name: name) do |t|
      t.mode = :team
      t.starts_at = starts_at
      t.ends_at = starts_at + 3.hours
      t.link_group_id = group
    end
  end
  puts "Seeded #{club.boats.count} boats and a linked league-night pair for #{club.name}."
end
