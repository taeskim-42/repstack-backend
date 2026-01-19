# frozen_string_literal: true

FactoryBot.define do
  factory :workout_set do
    association :workout_session
    sequence(:exercise_name) { |n| ["Push-up", "Squat", "Deadlift", "Bench Press", "Pull-up"][n % 5] }
    weight { 50.0 }
    weight_unit { "kg" }
    reps { 10 }
    duration_seconds { nil }
    notes { nil }

    trait :bodyweight do
      weight { nil }
      weight_unit { nil }
    end

    trait :timed do
      reps { nil }
      duration_seconds { 60 }
    end

    trait :in_lbs do
      weight_unit { "lbs" }
      weight { 110.0 }
    end

    trait :with_notes do
      notes { "Good form, increase weight next time" }
    end
  end
end
