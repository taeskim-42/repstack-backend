# frozen_string_literal: true

FactoryBot.define do
  factory :exercise_video_clip do
    youtube_video
    sequence(:exercise_name) { |n| "exercise_#{n}" }
    clip_type { "technique" }
    sequence(:title) { |n| "Exercise Guide #{n}" }
    content { "Detailed technique explanation for proper form." }
    summary { "Key technique points" }
    timestamp_start { 10.0 }
    timestamp_end { 90.0 }
    source_language { "ko" }

    trait :technique do
      clip_type { "technique" }
    end

    trait :form_check do
      clip_type { "form_check" }
    end

    trait :pro_tip do
      clip_type { "pro_tip" }
    end

    trait :common_mistake do
      clip_type { "common_mistake" }
    end

    trait :english do
      source_language { "en" }
    end
  end
end
