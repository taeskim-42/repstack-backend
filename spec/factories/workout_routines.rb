# frozen_string_literal: true

FactoryBot.define do
  factory :workout_routine do
    association :user
    level { "beginner" }
    week_number { 1 }
    day_number { 1 }
    workout_type { "strength" }
    day_of_week { "Monday" }
    estimated_duration { 45 }
    is_completed { false }
    completed_at { nil }
    generated_at { Time.current }

    trait :completed do
      is_completed { true }
      completed_at { Time.current }
    end

    trait :intermediate do
      level { "intermediate" }
    end

    trait :advanced do
      level { "advanced" }
    end

    trait :with_exercises do
      after(:create) do |routine|
        create_list(:routine_exercise, 4, workout_routine: routine)
      end
    end

    trait :monday do
      day_of_week { "Monday" }
      day_number { 1 }
    end

    trait :friday do
      day_of_week { "Friday" }
      day_number { 5 }
    end
  end
end
