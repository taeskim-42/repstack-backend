# frozen_string_literal: true

FactoryBot.define do
  factory :routine_exercise do
    association :workout_routine
    sequence(:order_index) { |n| n }
    sequence(:exercise_name) { |n| ["푸시업", "스쿼트", "플랭크", "턱걸이"][n % 4] }
    target_muscle { %w[chest legs core back][rand(4)] }
    sets { 3 }
    reps { 10 }
    weight { nil }
    weight_description { "체중" }
    bpm { 60 }
    rest_duration_seconds { 60 }
    range_of_motion { "full" }
    how_to { "운동 설명" }
    purpose { "근력 강화" }

    trait :weighted do
      weight { 20.0 }
      weight_description { "20kg" }
    end

    trait :chest do
      exercise_name { "벤치프레스" }
      target_muscle { "chest" }
    end

    trait :back do
      exercise_name { "턱걸이" }
      target_muscle { "back" }
    end

    trait :legs do
      exercise_name { "스쿼트" }
      target_muscle { "legs" }
    end

    trait :core do
      exercise_name { "플랭크" }
      target_muscle { "core" }
      reps { 1 }
      rest_duration_seconds { 30 }
    end
  end
end
