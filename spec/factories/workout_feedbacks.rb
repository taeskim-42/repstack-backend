# frozen_string_literal: true

FactoryBot.define do
  factory :workout_feedback do
    user
    feedback { '운동이 좋았어요' }
    feedback_type { 'DIFFICULTY' }
    rating { 4 }
    would_recommend { true }
    suggestions { [] }
  end
end
