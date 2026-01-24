# frozen_string_literal: true

module Mutations
  class SubmitFitnessTest < BaseMutation
    description "Submit basic fitness test results (push-ups, squats, assisted pull-ups) for initial level assessment"

    argument :pushup_count, Integer, required: true,
      description: "Number of push-ups completed at 30 BPM tempo"
    argument :squat_count, Integer, required: true,
      description: "Number of squats completed at 30 BPM tempo"
    argument :pullup_count, Integer, required: true,
      description: "Number of assisted pull-ups completed at 30 BPM tempo"
    argument :test_duration_seconds, Integer, required: false,
      description: "Total test duration in seconds (optional metadata)"
    argument :device_model, String, required: false,
      description: "Device model used for testing (optional metadata)"

    field :result, Types::FitnessTestResultType, null: true
    field :errors, [String], null: false

    def resolve(pushup_count:, squat_count:, pullup_count:, test_duration_seconds: nil, device_model: nil)
      user = context[:current_user]
      return { result: nil, errors: ["인증이 필요합니다."] } unless user

      # Validate inputs
      validation_errors = validate_inputs(pushup_count, squat_count, pullup_count)
      return { result: nil, errors: validation_errors } if validation_errors.any?

      # Check if user already has level assessed
      if user.user_profile&.level_assessed_at.present?
        return {
          result: nil,
          errors: ["이미 레벨이 측정되었습니다. 레벨 변경은 승급 테스트를 통해 진행해주세요."]
        }
      end

      # Evaluate fitness test
      service = AiTrainer::FitnessTestService.new(user: user)
      result = service.evaluate(
        pushup_count: pushup_count,
        squat_count: squat_count,
        pullup_count: pullup_count
      )

      # Apply result to user profile
      unless service.apply_to_profile(result)
        return {
          result: nil,
          errors: ["프로필 업데이트에 실패했습니다."]
        }
      end

      # Log metadata if provided
      log_test_metadata(user, test_duration_seconds, device_model) if test_duration_seconds || device_model

      # Format response
      {
        result: format_result(result),
        errors: []
      }
    end

    private

    def validate_inputs(pushup, squat, pullup)
      errors = []
      errors << "푸쉬업 횟수는 0 이상이어야 합니다." if pushup.negative?
      errors << "스쿼트 횟수는 0 이상이어야 합니다." if squat.negative?
      errors << "턱걸이 횟수는 0 이상이어야 합니다." if pullup.negative?
      errors << "입력값이 비정상적으로 높습니다." if pushup > 200 || squat > 300 || pullup > 100
      errors
    end

    def format_result(result)
      {
        success: result[:success],
        fitness_score: result[:fitness_score],
        assigned_level: result[:assigned_level],
        assigned_tier: result[:assigned_tier],
        message: result[:message],
        recommendations: result[:recommendations],
        exercise_results: format_exercise_results(result[:exercise_results]),
        errors: []
      }
    end

    def format_exercise_results(results)
      return nil unless results

      {
        pushup: format_single_result(results[:pushup]),
        squat: format_single_result(results[:squat]),
        pullup: format_single_result(results[:pullup])
      }
    end

    def format_single_result(result)
      return nil unless result

      {
        count: result[:count],
        tier: result[:tier].to_s,
        tier_korean: result[:tier_korean],
        points: result[:points]
      }
    end

    def log_test_metadata(user, duration, device)
      Rails.logger.info(
        "[FitnessTest] User #{user.id} completed test - " \
        "Duration: #{duration}s, Device: #{device}"
      )
    end
  end
end
