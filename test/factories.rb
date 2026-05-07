FactoryBot.define do
  # Factories declared here; each model task adds its own.
  factory :club do
    sequence(:name) { |n| "Club #{n}" }
  end

  factory :user do
    association :club
    sequence(:name) { |n| "Angler #{n}" }
    sequence(:email) { |n| "angler#{n}@example.com" }
  end

  factory :species do
    association :club
    sequence(:name) { |n| "Species #{n}" }
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
