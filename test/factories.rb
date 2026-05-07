FactoryBot.define do
  # Factories declared here; each model task adds its own.
  factory :club do
    sequence(:name) { |n| "Club #{n}" }
  end

  factory :user do
    sequence(:name) { |n| "Angler #{n}" }
    sequence(:email) { |n| "angler#{n}@example.com" }

    # Mirror prod state: every user should have at least one ClubMembership so
    # current_club resolves on sign-in. Tests that need a clubless user can
    # pass `club: nil` explicitly.
    transient do
      club { build(:club) }
      role { :member }
    end

    after(:create) do |u, ev|
      next unless ev.club
      ev.club.save! if ev.club.new_record?
      next if u.club_memberships.exists?(club_id: ev.club.id)
      u.club_memberships.create!(club: ev.club, role: ev.role, deactivated_at: u.deactivated_at)
    end
  end

  factory :species do
    sequence(:name) { |n| "Species #{n}" }

    # Accept and ignore club: for backwards compat with tests written when
    # species had a club_id. Species are global after the multi-club refactor.
    transient do
      club { nil }
    end
  end

  factory :tournament do
    association :club
    sequence(:name) { |n| "Tournament #{n}" }
    kind { :event }
    mode { :solo }
    starts_at { 1.hour.ago }
    ends_at { 1.hour.from_now }
  end

  factory :scoring_slot do
    association :tournament
    association :species
    slot_count { 1 }
  end

  factory :tournament_entry do
    association :tournament
  end

  factory :tournament_entry_member do
    association :tournament_entry
    association :user
  end

  factory :tournament_judge do
    association :tournament
    association :user
  end

  factory :catch do
    association :user
    association :species
    length_inches { 18.5 }
    captured_at_device { Time.current }
    status { :synced }
    sequence(:client_uuid) { |n| "client-uuid-#{n}" }

    after(:build) do |c|
      unless c.photo.attached?
        c.photo.attach(
          io: File.open(Rails.root.join("test/fixtures/files/sample_walleye.jpg")),
          filename: "sample_walleye.jpg",
          content_type: "image/jpeg"
        )
      end
    end
  end

  factory :catch_placement do
    association :catch
    association :tournament
    association :tournament_entry
    association :species
    slot_index { 0 }
    active { true }
  end

  factory :push_subscription do
    association :user
    sequence(:endpoint) { |n| "https://example/sub/#{n}" }
    p256dh { "p256dh-key" }
    auth { "auth-key" }
  end

  factory :judge_action do
    association :judge_user, factory: :user
    association :catch
    action { :approve }
  end

  factory :tournament_template do
    association :club
    sequence(:name) { |n| "Template #{n}" }
    mode { :solo }
  end

  factory :club_membership do
    association :user
    association :club
    role { :member }
  end
end
