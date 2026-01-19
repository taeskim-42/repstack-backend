# frozen_string_literal: true

FactoryBot.define do
  factory :workout_session do
    association :user
    sequence(:name) { |n| "Workout Session #{n}" }
    start_time { Time.current }
    end_time { nil }
    notes { nil }

    trait :active do
      end_time { nil }
    end

    trait :completed do
      end_time { Time.current + 1.hour }
    end

    trait :with_sets do
      after(:create) do |session|
        create_list(:workout_set, 3, workout_session: session)
      end
    end

    trait :long_workout do
      start_time { 2.hours.ago }
      end_time { Time.current }
    end
  end
end
