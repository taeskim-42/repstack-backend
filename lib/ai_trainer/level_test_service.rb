# frozen_string_literal: true

require_relative "constants"

module AiTrainer
  # Handles level testing and promotion (승급 시험)
  # Gamification element - users take tests to level up
  class LevelTestService
    include Constants

    attr_reader :user, :current_level

    def initialize(user:)
      @user = user
      @current_level = user.user_profile&.numeric_level || user.user_profile&.level || 1
    end

    # Generate a level test based on current level
    def generate_test
      next_level = [@current_level + 1, 8].min
      criteria = Constants::LEVEL_TEST_CRITERIA[next_level]
      height = @user.user_profile&.height || 170

      {
        test_id: generate_test_id,
        current_level: @current_level,
        target_level: next_level,
        test_type: determine_test_type,
        criteria: format_criteria(criteria, height),
        exercises: generate_test_exercises(criteria, height),
        instructions: generate_instructions(next_level),
        time_limit_minutes: calculate_time_limit,
        pass_conditions: generate_pass_conditions(criteria, height)
      }
    end

    # Evaluate test results
    def evaluate_results(test_results)
      next_level = [@current_level + 1, 8].min
      criteria = Constants::LEVEL_TEST_CRITERIA[next_level]
      height = @user.user_profile&.height || 170

      passed_exercises = []
      failed_exercises = []

      # Check each exercise result
      test_results[:exercises]&.each do |result|
        exercise_type = result[:exercise_type]&.to_sym
        weight_lifted = result[:weight_kg].to_f
        reps_completed = result[:reps].to_i

        required_weight = calculate_required_weight(criteria, exercise_type, height)
        required_reps = 1 # 1RM test

        if weight_lifted >= required_weight && reps_completed >= required_reps
          passed_exercises << {
            exercise: exercise_type,
            required: required_weight,
            achieved: weight_lifted,
            status: :passed
          }
        else
          failed_exercises << {
            exercise: exercise_type,
            required: required_weight,
            achieved: weight_lifted,
            status: :failed,
            gap: required_weight - weight_lifted
          }
        end
      end

      passed = failed_exercises.empty?

      {
        test_id: test_results[:test_id],
        passed: passed,
        new_level: passed ? next_level : @current_level,
        results: {
          passed_exercises: passed_exercises,
          failed_exercises: failed_exercises,
          total_exercises: passed_exercises.length + failed_exercises.length,
          pass_rate: (passed_exercises.length.to_f / (passed_exercises.length + failed_exercises.length) * 100).round(1)
        },
        feedback: generate_feedback(passed, failed_exercises),
        next_steps: generate_next_steps(passed, failed_exercises)
      }
    end

    # Check if user is eligible for level test
    def eligible_for_test?
      profile = @user.user_profile
      return { eligible: false, reason: "프로필이 없습니다." } unless profile

      # Check last test date (cooldown period)
      last_test = profile.last_level_test_at

      # Skip workout count check for initial level test (never taken a test before)
      unless last_test.nil?
        # Check minimum workouts completed (only for promotion tests)
        completed_workouts = @user.workout_sessions.where.not(end_time: nil).count
        min_workouts = minimum_workouts_for_test

        if completed_workouts < min_workouts
          return {
            eligible: false,
            reason: "승급 시험을 위해 최소 #{min_workouts}회 운동을 완료해야 합니다.",
            current_workouts: completed_workouts,
            required_workouts: min_workouts
          }
        end
      end

      # Check cooldown period
      if last_test && last_test > 7.days.ago
        days_remaining = ((last_test + 7.days - Time.current) / 1.day).ceil
        return {
          eligible: false,
          reason: "승급 시험은 7일에 한 번만 가능합니다.",
          days_until_eligible: days_remaining
        }
      end

      # Check if already at max level
      if @current_level >= 8
        return {
          eligible: false,
          reason: "이미 최고 레벨에 도달했습니다!"
        }
      end

      {
        eligible: true,
        current_level: @current_level,
        target_level: @current_level + 1,
        target_tier: Constants.tier_for_level(@current_level + 1)
      }
    end

    private

    def generate_test_id
      "LT-#{@current_level}-#{Time.current.to_i}-#{SecureRandom.hex(4)}"
    end

    def determine_test_type
      case Constants.tier_for_level(@current_level + 1)
      when "beginner"
        :form_test # Focus on form for beginners
      when "intermediate"
        :strength_test # 1RM tests for intermediate
      when "advanced"
        :comprehensive_test # Multiple aspects for advanced
      end
    end

    def format_criteria(criteria, height)
      {
        bench_press_kg: calculate_required_weight(criteria, :bench, height),
        squat_kg: calculate_required_weight(criteria, :squat, height),
        deadlift_kg: calculate_required_weight(criteria, :deadlift, height),
        description: criteria[:description]
      }
    end

    def calculate_required_weight(criteria, exercise_type, height)
      ratio_key = "#{exercise_type}_ratio".to_sym
      ratio = criteria[ratio_key] || 1.0
      base_weight = case exercise_type
                    when :bench then height - 100
                    when :squat then height - 100 + 20
                    when :deadlift then height - 100 + 40
                    else height - 100
                    end

      (base_weight * ratio).round(1)
    end

    def generate_test_exercises(criteria, height)
      [
        {
          order: 1,
          exercise_name: "벤치프레스",
          exercise_type: :bench,
          target_weight_kg: calculate_required_weight(criteria, :bench, height),
          target_reps: 1,
          rest_minutes: 3,
          instructions: "최대 1회 중량 테스트. 안전을 위해 스팟터와 함께 수행하세요."
        },
        {
          order: 2,
          exercise_name: "스쿼트",
          exercise_type: :squat,
          target_weight_kg: calculate_required_weight(criteria, :squat, height),
          target_reps: 1,
          rest_minutes: 3,
          instructions: "최대 1회 중량 테스트. 풀 스쿼트로 수행하세요."
        },
        {
          order: 3,
          exercise_name: "데드리프트",
          exercise_type: :deadlift,
          target_weight_kg: calculate_required_weight(criteria, :deadlift, height),
          target_reps: 1,
          rest_minutes: 3,
          instructions: "최대 1회 중량 테스트. 허리를 곧게 유지하세요."
        }
      ]
    end

    def generate_instructions(target_level)
      tier = Constants.tier_for_level(target_level)
      grade = find_grade_for_level(target_level)

      [
        "🎯 레벨 #{target_level} 승급 시험입니다!",
        "목표 등급: #{tier.upcase} (#{grade})",
        "",
        "⚠️ 주의사항:",
        "1. 충분한 워밍업 후 시작하세요",
        "2. 각 운동 사이에 3분 휴식을 취하세요",
        "3. 안전이 최우선입니다 - 무리하지 마세요",
        "4. 스팟터와 함께 수행하는 것을 권장합니다",
        "",
        "💪 행운을 빕니다!"
      ]
    end

    def find_grade_for_level(level)
      grade = Constants::GRADES.find { |_k, v| v[:levels].include?(level) }
      grade ? grade[1][:korean] : "정상인"
    end

    def calculate_time_limit
      30 # 30 minutes for the test
    end

    def generate_pass_conditions(criteria, height)
      {
        all_exercises_required: true,
        minimum_exercises: 3,
        exercises: [
          { exercise: "벤치프레스", weight_kg: calculate_required_weight(criteria, :bench, height), reps: 1 },
          { exercise: "스쿼트", weight_kg: calculate_required_weight(criteria, :squat, height), reps: 1 },
          { exercise: "데드리프트", weight_kg: calculate_required_weight(criteria, :deadlift, height), reps: 1 }
        ]
      }
    end

    def minimum_workouts_for_test
      case @current_level
      when 1..2 then 10
      when 3..5 then 20
      when 6..7 then 30
      else 10
      end
    end

    def generate_feedback(passed, failed_exercises)
      if passed
        [
          "🎉 축하합니다! 승급 시험을 통과했습니다!",
          "새로운 레벨에서 더 강해진 당신을 기대합니다.",
          "다음 목표를 향해 계속 도전하세요!"
        ]
      else
        feedback = ["아쉽게도 이번 시험은 통과하지 못했습니다."]

        failed_exercises.each do |failed|
          feedback << "- #{failed[:exercise]}: #{failed[:gap].round(1)}kg 부족"
        end

        feedback << ""
        feedback << "포기하지 마세요! 꾸준한 훈련으로 반드시 성장할 수 있습니다."
        feedback
      end
    end

    def generate_next_steps(passed, failed_exercises)
      if passed
        [
          "새로운 레벨에 맞는 루틴이 생성됩니다",
          "다음 승급까지 열심히 훈련하세요",
          "7일 후 다시 승급 시험에 도전할 수 있습니다"
        ]
      else
        steps = ["약점 부위 강화 훈련을 추천합니다"]

        failed_exercises.each do |failed|
          case failed[:exercise]
          when :bench
            steps << "- 가슴/삼두 운동 비중 증가 권장"
          when :squat
            steps << "- 하체 운동 비중 증가 권장"
          when :deadlift
            steps << "- 등/햄스트링 운동 비중 증가 권장"
          end
        end

        steps << "7일 후 다시 도전할 수 있습니다"
        steps
      end
    end
  end
end
