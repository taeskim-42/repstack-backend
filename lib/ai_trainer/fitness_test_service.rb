# frozen_string_literal: true

require_relative "constants"

module AiTrainer
  # Handles basic fitness assessment using bodyweight exercises
  # Used for initial level placement based on push-ups, squats, and assisted pull-ups
  class FitnessTestService
    include Constants

    # Scoring criteria for bodyweight exercises
    # Based on general fitness standards adjusted for the app's level system
    SCORING_CRITERIA = {
      pushup: {
        # Reps ranges for each score tier
        poor: 0..9,
        fair: 10..19,
        good: 20..34,
        excellent: 35..49,
        elite: 50..Float::INFINITY
      },
      squat: {
        poor: 0..14,
        fair: 15..29,
        good: 30..49,
        excellent: 50..74,
        elite: 75..Float::INFINITY
      },
      pullup: {
        # Assisted pull-ups, so criteria is adjusted
        poor: 0..2,
        fair: 3..7,
        good: 8..14,
        excellent: 15..24,
        elite: 25..Float::INFINITY
      }
    }.freeze

    # Score to points mapping
    TIER_POINTS = {
      poor: 1,
      fair: 2,
      good: 3,
      excellent: 4,
      elite: 5
    }.freeze

    # Total points to level mapping (max 15 points)
    POINTS_TO_LEVEL = {
      3..4 => 1,    # All poor/fair
      5..6 => 2,    # Mixed poor/fair
      7..8 => 3,    # Mostly fair/good
      9..10 => 4,   # Mixed good
      11..12 => 5,  # Mostly good/excellent
      13..14 => 6,  # Excellent level
      15..15 => 7   # Elite (rarely achievable on first test)
    }.freeze

    attr_reader :user

    def initialize(user:)
      @user = user
    end

    # Evaluate fitness test results and assign initial level
    # @param pushup_count [Integer] Number of push-ups completed
    # @param squat_count [Integer] Number of squats completed
    # @param pullup_count [Integer] Number of assisted pull-ups completed
    # @return [Hash] Evaluation result with score and assigned level
    def evaluate(pushup_count:, squat_count:, pullup_count:)
      # Calculate individual scores
      pushup_result = score_exercise(:pushup, pushup_count)
      squat_result = score_exercise(:squat, squat_count)
      pullup_result = score_exercise(:pullup, pullup_count)

      # Calculate total points
      total_points = pushup_result[:points] + squat_result[:points] + pullup_result[:points]

      # Determine level from points
      assigned_level = determine_level(total_points)
      assigned_tier = Constants.tier_for_level(assigned_level)

      # Calculate fitness score (0-100)
      fitness_score = calculate_fitness_score(total_points)

      {
        success: true,
        fitness_score: fitness_score,
        total_points: total_points,
        max_points: 15,
        assigned_level: assigned_level,
        assigned_tier: assigned_tier,
        exercise_results: {
          pushup: pushup_result.merge(count: pushup_count),
          squat: squat_result.merge(count: squat_count),
          pullup: pullup_result.merge(count: pullup_count)
        },
        message: generate_message(fitness_score, assigned_tier),
        recommendations: generate_recommendations(pushup_result, squat_result, pullup_result)
      }
    end

    # Apply fitness test result to user profile
    # @param result [Hash] Result from evaluate method
    # @return [Boolean] Success status
    def apply_to_profile(result)
      profile = @user.user_profile
      return false unless profile

      profile.update!(
        numeric_level: result[:assigned_level],
        current_level: result[:assigned_tier],
        level_assessed_at: Time.current,
        fitness_factors: profile.fitness_factors.merge(
          "fitness_test_result" => {
            "score" => result[:fitness_score],
            "level" => result[:assigned_level],
            "tested_at" => Time.current.iso8601,
            "exercise_results" => result[:exercise_results]
          }
        )
      )

      true
    rescue ActiveRecord::RecordInvalid => e
      Rails.logger.error("[FitnessTestService] Failed to update profile: #{e.message}")
      false
    end

    private

    def score_exercise(exercise_type, count)
      criteria = SCORING_CRITERIA[exercise_type]
      tier = criteria.find { |_tier, range| range.include?(count) }&.first || :poor
      points = TIER_POINTS[tier]

      {
        tier: tier,
        tier_korean: tier_korean(tier),
        points: points
      }
    end

    def tier_korean(tier)
      case tier
      when :poor then "부족"
      when :fair then "보통"
      when :good then "양호"
      when :excellent then "우수"
      when :elite then "엘리트"
      end
    end

    def determine_level(total_points)
      POINTS_TO_LEVEL.find { |range, _level| range.include?(total_points) }&.last || 1
    end

    def calculate_fitness_score(total_points)
      # Convert 3-15 points to 0-100 score
      # 3 points = 20, 15 points = 100
      base_score = ((total_points - 3) / 12.0 * 80 + 20).round
      [base_score, 100].min
    end

    def generate_message(score, tier)
      case tier
      when "beginner"
        "기초 체력 측정이 완료되었습니다! 💪 초급 단계에서 시작합니다. 꾸준한 운동으로 성장해 나가요!"
      when "intermediate"
        "좋은 기초 체력을 보유하고 계시네요! 🔥 중급 단계에서 시작합니다. 더 높은 목표를 향해 도전해보세요!"
      when "advanced"
        "뛰어난 체력입니다! 🏆 고급 단계에서 시작합니다. 전문적인 훈련으로 한계를 넘어보세요!"
      else
        "측정 완료! 맞춤형 훈련을 시작합니다."
      end
    end

    def generate_recommendations(pushup, squat, pullup)
      recommendations = []

      if pushup[:tier] == :poor || pushup[:tier] == :fair
        recommendations << "상체 밀기 운동(푸쉬업, 벤치프레스) 강화 권장"
      end

      if squat[:tier] == :poor || squat[:tier] == :fair
        recommendations << "하체 운동(스쿼트, 레그프레스) 강화 권장"
      end

      if pullup[:tier] == :poor || pullup[:tier] == :fair
        recommendations << "상체 당기기 운동(턱걸이, 랫풀다운) 강화 권장"
      end

      if recommendations.empty?
        recommendations << "전반적으로 좋은 체력입니다. 균형 잡힌 훈련을 유지하세요!"
      end

      recommendations
    end
  end
end
