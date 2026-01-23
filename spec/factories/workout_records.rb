# frozen_string_literal: true

FactoryBot.define do
  factory :workout_record do
    user
    workout_session
    date { Time.current }
    total_duration { 3600 }
    perceived_exertion { 7 }
    completion_status { "COMPLETED" }
    calories_burned { 300 }
    average_heart_rate { 140 }

    trait :partial do
      completion_status { "PARTIAL" }
    end

    trait :skipped do
      completion_status { "SKIPPED" }
    end
  end
end
