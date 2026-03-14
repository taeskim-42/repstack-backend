# frozen_string_literal: true

module AiTrainer
  module LevelTest
    # Evaluates promotion readiness using estimated 1RMs from workout history.
    # Depends on host class providing: @user, @current_level, calculate_required_weight,
    # EXERCISE_MAPPINGS, LlmGateway
    module PromotionEvaluator
      # Main entry point: evaluate whether user meets promotion criteria
      def evaluate_promotion_readiness
        height = @user.user_profile&.height || 170
        next_level = [ @current_level + 1, 8 ].min
        criteria = Constants::LEVEL_TEST_CRITERIA[next_level]

        estimated_1rms = calculate_estimated_1rms

        required = {
          bench: calculate_required_weight(criteria, :bench, height),
          squat: calculate_required_weight(criteria, :squat, height),
          deadlift: calculate_required_weight(criteria, :deadlift, height)
        }

        results = {}
        all_passed = true

        %i[bench squat deadlift].each do |exercise|
          estimated = estimated_1rms[exercise]
          req = required[exercise]

          results[exercise] = build_exercise_result(exercise, estimated, req)
          all_passed = false unless results[exercise][:status] == :passed
        end

        ai_feedback = get_ai_promotion_feedback(results, all_passed, next_level)

        {
          eligible: all_passed,
          current_level: @current_level,
          target_level: next_level,
          estimated_1rms: estimated_1rms,
          required_1rms: required,
          exercise_results: results,
          ai_feedback: ai_feedback,
          recommendation: all_passed ? :ready_for_promotion : :continue_training
        }
      end

      # Calculate estimated 1RM for each lift using Epley formula
      # 1RM = weight × (1 + reps/30)
      def calculate_estimated_1rms
        sessions = @user.workout_sessions
                        .where.not(end_time: nil)
                        .where("created_at > ?", 8.weeks.ago)
                        .includes(:workout_sets)

        estimates = { bench: nil, squat: nil, deadlift: nil }

        WeightCalculator::EXERCISE_MAPPINGS.each do |exercise_type, names|
          best = find_best_estimated_1rm(sessions, names)
          estimates[exercise_type] = best if best
        end

        estimates
      end

      private

      def build_exercise_result(exercise, estimated, req)
        if estimated.nil?
          { estimated_1rm: nil, required: req, status: :no_data, message: "#{exercise_korean(exercise)} 기록이 부족합니다" }
        elsif estimated >= req
          { estimated_1rm: estimated.round(1), required: req, status: :passed, surplus: (estimated - req).round(1) }
        else
          { estimated_1rm: estimated.round(1), required: req, status: :failed, gap: (req - estimated).round(1) }
        end
      end

      def find_best_estimated_1rm(sessions, exercise_names)
        best = nil

        sessions.each do |session|
          session.workout_sets.each do |set|
            next unless exercise_names.any? { |name| set.exercise_name&.downcase&.include?(name.downcase) }
            next unless set.weight.present? && set.reps.present? && set.reps > 0

            weight_kg = set.weight_in_kg
            next unless weight_kg && weight_kg > 0

            estimated = set.reps == 1 ? weight_kg : weight_kg * (1 + set.reps / 30.0)
            best = estimated if best.nil? || estimated > best
          end
        end

        best
      end

      def get_ai_promotion_feedback(results, all_passed, target_level)
        prompt = build_promotion_prompt(results, all_passed, target_level)
        response = LlmGateway.chat(prompt: prompt, task: :level_assessment)

        if response[:success]
          response[:content]
        else
          all_passed ? default_pass_message(target_level) : default_fail_message(results)
        end
      end

      def build_promotion_prompt(results, all_passed, target_level)
        tier = Constants.tier_for_level(target_level)

        <<~PROMPT
          사용자의 승급 심사 결과를 분석하고 피드백을 제공해주세요.

          현재 레벨: #{@current_level}
          목표 레벨: #{target_level} (#{tier})

          운동 기록 기반 추정 1RM 결과:
          #{format_results_for_prompt(results)}

          심사 결과: #{all_passed ? '통과' : '미달'}

          #{all_passed ? '축하 메시지와 다음 목표에 대한 조언을 해주세요.' : '부족한 부분에 대한 구체적인 훈련 조언을 해주세요.'}

          2-3문장으로 간결하게 작성해주세요. 이모지를 적절히 사용해주세요.
        PROMPT
      end

      def format_results_for_prompt(results)
        results.map do |exercise, data|
          name = exercise_korean(exercise)
          case data[:status]
          when :passed then "- #{name}: #{data[:estimated_1rm]}kg (기준 #{data[:required]}kg) ✅ +#{data[:surplus]}kg"
          when :failed then "- #{name}: #{data[:estimated_1rm]}kg (기준 #{data[:required]}kg) ❌ -#{data[:gap]}kg"
          when :no_data then "- #{name}: 기록 없음 (기준 #{data[:required]}kg)"
          end
        end.join("\n")
      end

      def exercise_korean(exercise)
        case exercise
        when :bench then "벤치프레스"
        when :squat then "스쿼트"
        when :deadlift then "데드리프트"
        else exercise.to_s
        end
      end

      def default_pass_message(target_level)
        "🎉 축하합니다! 레벨 #{target_level} 승급 조건을 충족했습니다. 꾸준한 노력의 결과입니다!"
      end

      def default_fail_message(results)
        failed = results.select { |_, v| v[:status] != :passed }
        exercises = failed.keys.map { |e| exercise_korean(e) }.join(", ")
        "💪 #{exercises} 기록이 조금 더 필요해요. 포기하지 말고 계속 도전하세요!"
      end
    end
  end
end
