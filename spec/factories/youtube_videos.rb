# frozen_string_literal: true

FactoryBot.define do
  factory :youtube_video do
    youtube_channel
    sequence(:video_id) { |n| "vid#{n.to_s.rjust(8, '0')}" }
    sequence(:title) { |n| "Fitness Video #{n}" }
    description { "Learn proper form and technique" }
    thumbnail_url { "https://i.ytimg.com/vi/#{video_id}/hqdefault.jpg" }
    duration_seconds { rand(300..1800) } # 5-30 minutes
    view_count { rand(1000..100_000) }
    like_count { rand(100..10_000) }
    published_at { rand(1..365).days.ago }
    analysis_status { "pending" }

    trait :pending do
      analysis_status { "pending" }
    end

    trait :analyzing do
      analysis_status { "analyzing" }
    end

    trait :completed do
      analysis_status { "completed" }
      analyzed_at { 1.hour.ago }
      category { "strength" }
      difficulty_level { "intermediate" }
      language { "ko" }
      raw_analysis do
        {
          category: "strength",
          difficulty_level: "intermediate",
          language: "ko",
          knowledge_chunks: [
            {
              type: "exercise_technique",
              content: "벤치프레스 자세 가이드",
              exercise_name: "bench_press",
              muscle_group: "chest"
            }
          ]
        }
      end
    end

    trait :failed do
      analysis_status { "failed" }
      analysis_error { "Failed to process video: API timeout" }
    end

    trait :with_transcript do
      transcript { "안녕하세요, 오늘은 벤치프레스 자세에 대해 알아보겠습니다..." }
    end
  end
end
