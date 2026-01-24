# frozen_string_literal: true

FactoryBot.define do
  factory :fitness_knowledge_chunk do
    youtube_video { association :youtube_video, :completed }
    knowledge_type { "exercise_technique" }
    content { "벤치프레스는 가슴 운동의 핵심입니다. 바를 내릴 때 가슴 중앙에 닿도록 하고, 견갑골을 모아 안정적인 자세를 유지하세요." }
    summary { "벤치프레스 기본 자세 가이드" }
    metadata { { source: "video_analysis", confidence: 0.95 } }

    trait :exercise_technique do
      knowledge_type { "exercise_technique" }
      exercise_name { "bench_press" }
      muscle_group { "chest" }
      difficulty_level { "intermediate" }
      content { "벤치프레스 수행 시 어깨 너비보다 약간 넓게 바를 잡고, 견갑골을 모아 안정적인 자세를 만드세요." }
    end

    trait :routine_design do
      knowledge_type { "routine_design" }
      content { "주 4일 상하체 분할: 월/목 상체, 화/금 하체. 각 부위별 4-5개 운동, 3-4세트씩 수행." }
      summary { "주 4일 분할 루틴 설계" }
    end

    trait :nutrition_recovery do
      knowledge_type { "nutrition_recovery" }
      content { "운동 후 30분 이내 단백질 섭취가 중요합니다. 체중 1kg당 1.6-2.2g의 단백질을 하루에 나눠 섭취하세요." }
      summary { "운동 후 영양 섭취 가이드" }
    end

    trait :form_check do
      knowledge_type { "form_check" }
      exercise_name { "squat" }
      muscle_group { "legs" }
      content { "스쿼트 시 무릎이 발끝보다 앞으로 나가도 괜찮지만, 발뒤꿈치가 떨어지지 않도록 주의하세요." }
      summary { "스쿼트 자세 체크포인트" }
    end

    trait :with_timestamp do
      timestamp_start { rand(0..300) }
      timestamp_end { timestamp_start + rand(30..120) }
    end

    trait :for_deadlift do
      exercise_name { "deadlift" }
      muscle_group { "back" }
      content { "데드리프트는 바를 몸에 최대한 가깝게 유지하며 들어올리세요. 등이 굽지 않도록 코어에 힘을 주세요." }
    end
  end
end
