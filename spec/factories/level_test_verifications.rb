# frozen_string_literal: true

FactoryBot.define do
  factory :level_test_verification do
    user
    sequence(:test_id) { |n| "LTV-3-#{Time.current.to_i}-#{format('%04x', n)}" }
    current_level { 3 }
    target_level { 4 }
    status { 'pending' }
    exercises { [] }
    passed { false }
    started_at { Time.current }

    trait :with_exercises do
      exercises do
        [
          {
            'exercise_type' => 'bench',
            'weight_kg' => 70.0,
            'passed' => true,
            'pose_score' => 85.0,
            'form_issues' => [],
            'verified_at' => Time.current.iso8601
          },
          {
            'exercise_type' => 'squat',
            'weight_kg' => 90.0,
            'passed' => true,
            'pose_score' => 80.0,
            'form_issues' => [],
            'verified_at' => Time.current.iso8601
          },
          {
            'exercise_type' => 'deadlift',
            'weight_kg' => 120.0,
            'passed' => true,
            'pose_score' => 82.0,
            'form_issues' => [],
            'verified_at' => Time.current.iso8601
          }
        ]
      end
    end

    trait :passed do
      with_exercises
      status { 'passed' }
      passed { true }
      new_level { 4 }
      ai_feedback { '🎉 축하합니다! 레벨 4 승급에 성공했습니다!' }
      completed_at { Time.current }
    end

    trait :failed do
      status { 'failed' }
      passed { false }
      new_level { 3 }
      ai_feedback { '💪 조금만 더 훈련하면 충분히 가능합니다!' }
      completed_at { Time.current }
      exercises do
        [
          {
            'exercise_type' => 'bench',
            'weight_kg' => 50.0,
            'passed' => false,
            'pose_score' => 75.0,
            'form_issues' => ['무게 부족: 10kg 더 필요'],
            'verified_at' => Time.current.iso8601
          }
        ]
      end
    end

    trait :in_progress do
      status { 'in_progress' }
    end
  end
end
