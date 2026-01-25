# frozen_string_literal: true

module Mutations
  # Test-only mutation to create a user in a specific state for testing
  # Creates a user who has completed onboarding and fitness test (Day 2)
  class CreateTestUser < BaseMutation
    description "테스트용: 온보딩+레벨테스트 완료된 2일차 유저 생성"

    # Arguments
    argument :name, String, required: false, description: "테스트 유저 이름 (기본: 테스트유저)"
    argument :level, Integer, required: false, description: "유저 레벨 1-8 (기본: 3)"
    argument :fitness_goal, String, required: false, description: "운동 목표 (기본: 근비대)"

    # Return type
    field :user, Types::UserType, null: true
    field :token, String, null: true, description: "JWT 토큰"
    field :errors, [String], null: false

    def resolve(name: nil, level: nil, fitness_goal: nil)
      # Only allow in development/test environments or when explicitly enabled
      unless Rails.env.development? || Rails.env.test? || ENV["ALLOW_TEST_FEATURES"] == "true"
        return { user: nil, token: nil, errors: ["테스트 환경에서만 사용 가능합니다"] }
      end

      name ||= "테스트유저"
      level ||= 3
      fitness_goal ||= "근비대"

      # Generate unique email for test user
      timestamp = Time.current.to_i
      email = "test_#{timestamp}@repstack.test"

      ActiveRecord::Base.transaction do
        # Create user (created 2 days ago)
        user = User.create!(
          email: email,
          name: name,
          password: "test1234!",
          created_at: 2.days.ago,
          updated_at: 2.days.ago
        )

        # Create profile with completed onboarding and fitness test
        experience = level_to_experience(level)

        profile = user.create_user_profile!(
          # Level from fitness test
          numeric_level: level,
          current_level: experience,  # beginner/intermediate/advanced
          fitness_goal: fitness_goal,
          week_number: 1,
          day_number: 2,  # Day 2

          # Onboarding completed
          onboarding_completed_at: 2.days.ago,
          level_assessed_at: 2.days.ago,

          # Fitness factors from onboarding conversation
          fitness_factors: {
            "assessment_state" => "completed",
            "experience_level" => experience,
            "onboarding_assessment" => {
              "experience_level" => experience,
              "fitness_goal" => fitness_goal,
              "summary" => "테스트 유저 - #{experience}, #{fitness_goal} 목표"
            },
            "collected_data" => {
              "experience" => experience_description(level),
              "frequency" => "주 4회",
              "goals" => fitness_goal
            }
          }
        )

        # Generate JWT token
        token = generate_token(user)

        { user: user, token: token, errors: [] }
      end
    rescue ActiveRecord::RecordInvalid => e
      { user: nil, token: nil, errors: [e.message] }
    rescue StandardError => e
      { user: nil, token: nil, errors: ["유저 생성 실패: #{e.message}"] }
    end

    private

    def level_to_experience(level)
      case level
      when 1..2 then "beginner"
      when 3..5 then "intermediate"
      else "advanced"
      end
    end

    def experience_description(level)
      case level
      when 1..2 then "헬스 시작한지 3개월"
      when 3..5 then "헬스 1년 정도"
      else "헬스 3년 이상"
      end
    end

    def generate_token(user)
      payload = {
        user_id: user.id,
        exp: 7.days.from_now.to_i
      }
      JWT.encode(payload, Rails.application.secret_key_base, "HS256")
    end
  end
end
