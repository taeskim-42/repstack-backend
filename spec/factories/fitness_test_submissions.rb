# frozen_string_literal: true

FactoryBot.define do
  factory :fitness_test_submission do
    user
    job_id { SecureRandom.uuid }
    status { "pending" }
    videos do
      [
        { "exercise_type" => "pushup", "video_key" => "fitness-tests/#{user.id}/pushup_#{SecureRandom.hex(4)}.mp4" },
        { "exercise_type" => "squat", "video_key" => "fitness-tests/#{user.id}/squat_#{SecureRandom.hex(4)}.mp4" },
        { "exercise_type" => "pullup", "video_key" => "fitness-tests/#{user.id}/pullup_#{SecureRandom.hex(4)}.mp4" }
      ]
    end
    analyses { {} }

    trait :processing do
      status { "processing" }
      started_at { Time.current }
    end

    trait :completed do
      status { "completed" }
      started_at { 5.minutes.ago }
      completed_at { Time.current }
      fitness_score { 75 }
      assigned_level { 3 }
      assigned_tier { "intermediate" }
      analyses do
        {
          "pushup" => {
            "success" => true,
            "exercise_type" => "pushup",
            "rep_count" => 20,
            "form_score" => 80,
            "issues" => [],
            "feedback" => "Good form!"
          },
          "squat" => {
            "success" => true,
            "exercise_type" => "squat",
            "rep_count" => 25,
            "form_score" => 75,
            "issues" => ["Knees slightly inward"],
            "feedback" => "Watch your knee alignment"
          },
          "pullup" => {
            "success" => true,
            "exercise_type" => "pullup",
            "rep_count" => 10,
            "form_score" => 70,
            "issues" => ["Partial range of motion"],
            "feedback" => "Try to get chin above the bar"
          }
        }
      end
      evaluation_result do
        {
          "success" => true,
          "fitness_score" => 75,
          "assigned_level" => 3,
          "assigned_tier" => "intermediate",
          "message" => "좋은 기초 체력을 보유하고 계시네요!",
          "recommendations" => ["균형 잡힌 훈련을 유지하세요"]
        }
      end
    end

    trait :failed do
      status { "failed" }
      started_at { 5.minutes.ago }
      completed_at { Time.current }
      error_message { "Video analysis failed: Timeout" }
    end

    trait :barbell do
      videos do
        [
          { "exercise_type" => "bench_press", "video_key" => "fitness-tests/#{user.id}/bench_press_#{SecureRandom.hex(4)}.mp4" },
          { "exercise_type" => "barbell_squat", "video_key" => "fitness-tests/#{user.id}/barbell_squat_#{SecureRandom.hex(4)}.mp4" },
          { "exercise_type" => "deadlift", "video_key" => "fitness-tests/#{user.id}/deadlift_#{SecureRandom.hex(4)}.mp4" }
        ]
      end
    end
  end
end
