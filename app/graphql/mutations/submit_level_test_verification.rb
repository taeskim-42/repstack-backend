# frozen_string_literal: true

module Mutations
  class SubmitLevelTestVerification < BaseMutation
    description "Submit level test verification from CoreML pose estimation"

    argument :input, Types::LevelTestVerificationInputType, required: true

    field :verification, Types::LevelTestVerificationType, null: true
    field :success, Boolean, null: false
    field :message, String, null: true
    field :errors, [String], null: true

    def resolve(input:)
      return auth_error unless current_user

      # Get user's current level info
      profile = current_user.user_profile
      return profile_error unless profile

      current_level = profile.numeric_level || 1
      target_level = [current_level + 1, 8].min

      # Check if already at max level
      if current_level >= 8
        return {
          verification: nil,
          success: false,
          message: "이미 최고 레벨에 도달했습니다!",
          errors: ["max_level_reached"]
        }
      end

      # Check eligibility (cooldown period)
      eligibility = AiTrainer::LevelTestService.new(user: current_user).eligible_for_test?
      unless eligibility[:eligible]
        return {
          verification: nil,
          success: false,
          message: eligibility[:reason],
          errors: ["not_eligible"]
        }
      end

      # Create or find verification record
      verification = find_or_create_verification(input, current_level, target_level)

      # Process each exercise verification
      process_exercises(verification, input.exercises, profile.height || 170)

      # Evaluate overall result
      evaluate_and_complete(verification)

      {
        verification: verification,
        success: verification.passed,
        message: verification.ai_feedback,
        errors: nil
      }
    rescue StandardError => e
      Rails.logger.error("[SubmitLevelTestVerification] Error: #{e.message}")
      {
        verification: nil,
        success: false,
        message: "검증 처리 중 오류가 발생했습니다.",
        errors: [e.message]
      }
    end

    private

    def auth_error
      {
        verification: nil,
        success: false,
        message: "인증이 필요합니다.",
        errors: ["unauthorized"]
      }
    end

    def profile_error
      {
        verification: nil,
        success: false,
        message: "프로필 설정이 필요합니다.",
        errors: ["profile_required"]
      }
    end

    def find_or_create_verification(input, current_level, target_level)
      test_id = input.test_id || generate_test_id(current_level)

      LevelTestVerification.find_or_create_by!(test_id: test_id) do |v|
        v.user = current_user
        v.current_level = current_level
        v.target_level = target_level
        v.status = 'in_progress'
      end
    end

    def generate_test_id(level)
      "LTV-#{level}-#{Time.current.to_i}-#{SecureRandom.hex(4)}"
    end

    def process_exercises(verification, exercises, height)
      criteria = AiTrainer::Constants::LEVEL_TEST_CRITERIA[verification.target_level]

      exercises.each do |exercise|
        exercise_type = exercise.exercise_type.to_sym
        required_weight = calculate_required_weight(criteria, exercise_type, height)

        # Check if weight meets requirement
        weight_passed = exercise.weight_kg >= required_weight

        # Check form quality (pose_score threshold: 70)
        form_passed = exercise.pose_score.nil? || exercise.pose_score >= 70

        # Both weight and form must pass
        passed = weight_passed && form_passed && exercise.form_issues.empty?

        verification.add_exercise_result(
          exercise_type: exercise_type,
          weight_kg: exercise.weight_kg,
          passed: passed,
          pose_score: exercise.pose_score,
          video_url: exercise.video_url,
          form_issues: build_form_issues(exercise, weight_passed, form_passed, required_weight)
        )
      end
    end

    def calculate_required_weight(criteria, exercise_type, height)
      ratio = criteria["#{exercise_type}_ratio".to_sym] || 1.0
      base_weight = case exercise_type
                    when :bench then height - 100
                    when :squat then height - 100 + 20
                    when :deadlift then height - 100 + 40
                    else height - 100
                    end

      (base_weight * ratio).round(1)
    end

    def build_form_issues(exercise, weight_passed, form_passed, required_weight)
      issues = exercise.form_issues.to_a.dup

      unless weight_passed
        gap = (required_weight - exercise.weight_kg).round(1)
        issues << "무게 부족: #{gap}kg 더 필요"
      end

      unless form_passed
        issues << "자세 점수 미달: #{exercise.pose_score&.round(1) || 0}/70"
      end

      issues
    end

    def evaluate_and_complete(verification)
      if verification.all_exercises_passed?
        # Get AI feedback for success
        feedback = get_ai_feedback(verification, true)
        verification.update!(ai_feedback: feedback)
        verification.complete_as_passed!
      else
        # Get AI feedback for failure
        feedback = get_ai_feedback(verification, false)
        verification.complete_as_failed!(feedback: feedback)
      end
    end

    def get_ai_feedback(verification, passed)
      prompt = build_feedback_prompt(verification, passed)

      response = AiTrainer::LlmGateway.chat(
        prompt: prompt,
        task: :level_assessment
      )

      if response[:success]
        response[:content]
      else
        passed ? default_success_message(verification) : default_failure_message(verification)
      end
    end

    def build_feedback_prompt(verification, passed)
      exercises_info = verification.exercises.map do |ex|
        status = ex['passed'] ? '✅ 통과' : '❌ 미달'
        issues = ex['form_issues']&.join(', ') || '없음'
        "- #{exercise_korean(ex['exercise_type'])}: #{ex['weight_kg']}kg #{status} (자세점수: #{ex['pose_score'] || 'N/A'}, 문제: #{issues})"
      end.join("\n")

      <<~PROMPT
        레벨 테스트 검증 결과를 분석하고 피드백을 제공해주세요.

        현재 레벨: #{verification.current_level}
        목표 레벨: #{verification.target_level}
        결과: #{passed ? '합격' : '불합격'}

        운동별 결과:
        #{exercises_info}

        #{passed ? '축하 메시지와 다음 단계 조언을 해주세요.' : '부족한 부분과 개선 방법을 구체적으로 조언해주세요.'}

        2-3문장으로 간결하게 작성하고, 이모지를 적절히 사용해주세요.
      PROMPT
    end

    def exercise_korean(type)
      case type.to_s
      when 'bench' then '벤치프레스'
      when 'squat' then '스쿼트'
      when 'deadlift' then '데드리프트'
      else type.to_s
      end
    end

    def default_success_message(verification)
      "🎉 축하합니다! 레벨 #{verification.target_level} 승급에 성공했습니다! 꾸준한 노력의 결과입니다. 💪"
    end

    def default_failure_message(verification)
      failed = verification.exercises.select { |ex| !ex['passed'] }
      names = failed.map { |ex| exercise_korean(ex['exercise_type']) }.join(', ')
      "💪 #{names}에서 아쉽게 기준에 미달했어요. 조금만 더 훈련하면 충분히 가능합니다!"
    end
  end
end
