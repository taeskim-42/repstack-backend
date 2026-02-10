# frozen_string_literal: true

FactoryBot.define do
  factory :user_profile do
    association :user
    height { 175.0 }
    weight { 70.0 }
    body_fat_percentage { 15.0 }
    current_level { "beginner" }
    week_number { 1 }
    day_number { 1 }
    fitness_goal { "Build muscle" }
    program_start_date { Date.current }
    # Both set = fully onboarded user (completed onboarding + fitness test)
    onboarding_completed_at { Time.current }
    level_assessed_at { Time.current }

    trait :beginner do
      current_level { "beginner" }
      week_number { 1 }
      day_number { 1 }
    end

    trait :intermediate do
      current_level { "intermediate" }
      week_number { 4 }
      day_number { 3 }
    end

    trait :advanced do
      current_level { "advanced" }
      week_number { 8 }
      day_number { 5 }
    end

    trait :week_end do
      day_number { 7 }
    end

    trait :no_measurements do
      height { nil }
      weight { nil }
      body_fat_percentage { nil }
    end

    # New user needing onboarding conversation
    trait :needs_assessment do
      onboarding_completed_at { nil }
      level_assessed_at { nil }
    end

  end
end
