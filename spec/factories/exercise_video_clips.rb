# frozen_string_literal: true

FactoryBot.define do
  factory :exercise_video_clip do
    youtube_video
    sequence(:exercise_name) { |n| "bench_press_#{n}" }
    clip_type { "technique" }
    sequence(:title) { |n| "Bench Press Technique #{n}" }
    content { "Keep your shoulder blades retracted throughout the movement." }
    summary { "어깨 견갑골을 모으고 가슴을 활짝 핀 상태에서 수행하세요." }
    timestamp_start { 30.0 }
    timestamp_end { 60.0 }
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
