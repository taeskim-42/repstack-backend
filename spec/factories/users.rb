# frozen_string_literal: true

FactoryBot.define do
  factory :user do
    sequence(:email) { |n| "user#{n}@example.com" }
    sequence(:name) { |n| "User #{n}" }
    password { "password123" }
    password_confirmation { "password123" }

    trait :with_profile do
      after(:create) do |user|
        create(:user_profile, user: user)
      end
    end

    trait :beginner do
      after(:create) do |user|
        create(:user_profile, :beginner, user: user)
      end
    end

    trait :intermediate do
      after(:create) do |user|
        create(:user_profile, :intermediate, user: user)
      end
    end

    trait :advanced do
      after(:create) do |user|
        create(:user_profile, :advanced, user: user)
      end
    end

    trait :apple_user do
      sequence(:apple_user_id) { |n| "apple_user_#{n}" }
      password { nil }
      password_confirmation { nil }
    end
  end
end
