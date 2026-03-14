# frozen_string_literal: true

# Analysis tool handlers: check condition, submit feedback, explain long-term plan.
module ChatToolHandlers
  module AnalysisTools
    extend ActiveSupport::Concern

    private

    def handle_check_condition(input)
      condition_text = input["condition_text"]
      return error_response("컨디션 상태를 알려주세요.") if condition_text.blank?

      result = AiTrainer::ConditionService.analyze_from_voice(
        user: user,
        text: condition_text
      )

      return error_response(result[:error] || "컨디션 분석에 실패했어요.") unless result[:success]

      condition = result[:condition]
      save_condition_log_from_result(condition)

      today_routine = WorkoutRoutine.where(user_id: user.id)
                                     .where("created_at >= ?", Time.current.beginning_of_day)
                                     .first

      unless today_routine
        prog = user.active_training_program
        if prog
          today_dow = Time.current.wday == 0 ? 7 : Time.current.wday
          today_routine = prog.workout_routines
                              .where(week_number: prog.current_week, day_number: today_dow)
                              .where(is_completed: false)
                              .includes(:routine_exercises)
                              .order(created_at: :desc)
                              .first
          today_routine = nil unless today_routine&.routine_exercises&.any?
        end
      end

      if today_routine
        routine_data = format_existing_routine(today_routine)
        routine_data = apply_routine_adjustments(routine_data, condition_modifier: result[:intensity_modifier] || 1.0)

        message = build_condition_response_message(condition, result)
        message += "\n\n컨디션을 반영해서 루틴을 조정했어요! 💪"

        return success_response(
          message: message,
          intent: "CONDITION_AND_ROUTINE",
          data: {
            condition: condition,
            intensity_modifier: result[:intensity_modifier],
            routine: routine_data,
            existing_routine_id: today_routine.id,
            suggestions: []
          }
        )
      end

      routine_result = AiTrainer.generate_routine(
        user: user,
        day_of_week: Time.current.wday == 0 ? 7 : Time.current.wday,
        condition_inputs: { text: condition_text, analyzed: condition },
        recent_feedbacks: user.workout_feedbacks.order(created_at: :desc).limit(5)
      )

      if routine_result.is_a?(Hash) && routine_result[:success] == false
        message = build_condition_response_message(condition, result)
        return success_response(
          message: message,
          intent: "CHECK_CONDITION",
          data: { condition: condition, suggestions: [] }
        )
      end

      if routine_result.is_a?(Hash) && routine_result[:rest_day]
        message = build_condition_response_message(condition, result)
        message += "\n\n오늘은 프로그램에 따른 휴식일이에요! 충분한 회복을 취하세요 💤"
        return success_response(
          message: message,
          intent: "REST_DAY",
          data: { rest_day: true, condition: condition, suggestions: [] }
        )
      end

      condition_msg = build_condition_acknowledgment(condition)
      routine_msg   = format_routine_for_display(routine_result)

      success_response(
        message: "#{condition_msg}\n\n#{routine_msg}",
        intent: "CONDITION_AND_ROUTINE",
        data: {
          condition: condition,
          intensity_modifier: result[:intensity_modifier],
          routine: routine_result,
          suggestions: []
        }
      )
    end

    def build_condition_acknowledgment(condition)
      messages = {
        "good"    => "컨디션 좋으시네요! 💪 오늘 강도 높여서 진행할게요!",
        "normal"  => "알겠어요! 👍 평소 강도로 진행할게요.",
        "tired"   => "피곤하시군요 😊 오늘은 가볍게 진행할게요!",
        "injured" => "아프신 부위가 있군요 🤕 해당 부위는 피해서 진행할게요."
      }
      messages[condition.to_s] || "컨디션 확인했어요! 👍"
    end

    def build_condition_response_message(condition, result)
      energy     = condition[:energy_level] || 3
      stress     = condition[:stress_level] || 3
      motivation = condition[:motivation] || 3

      avg_score = (energy + (6 - stress) + motivation) / 3.0

      status_emoji, status_text = if avg_score >= 4
        [ "💪", "좋은 컨디션" ]
      elsif avg_score >= 3
        [ "👍", "괜찮은 컨디션" ]
      elsif avg_score >= 2
        [ "😊", "조금 피곤한 컨디션" ]
      else
        [ "🌙", "휴식이 필요한 컨디션" ]
      end

      msg = "#{status_emoji} 오늘 #{status_text}이시네요! 컨디션을 기록했어요.\n\n"
      msg += "#{result[:interpretation]}\n\n" if result[:interpretation].present?

      if result[:adaptations].present? && result[:adaptations].any?
        msg += "📝 **운동 시 참고하세요:**\n"
        result[:adaptations].first(3).each { |a| msg += "• #{a}\n" }
        msg += "\n"
      end

      suggestions = build_condition_suggestions(condition, result)
      msg += "오늘 어떤 운동을 해볼까요? 루틴이 필요하면 말씀해주세요!" if suggestions.any?

      msg
    end

    def build_condition_suggestions(condition, result)
      suggestions = []
      energy    = condition[:energy_level] || 3
      intensity = result[:intensity_modifier] || 1.0

      if energy <= 2 || intensity < 0.8
        suggestions << "가벼운 루틴 만들어줘"
        suggestions << "스트레칭만 할래"
      elsif energy >= 4
        suggestions << "오늘 루틴 만들어줘"
        suggestions << "강하게 운동하고 싶어"
      else
        suggestions << "오늘 루틴 만들어줘"
      end

      suggestions
    end

    def generate_routine_with_condition(condition, intensity)
      condition_messages = {
        good:   "컨디션 좋으시네요! 💪 오늘은 **강도 110%**로 진행할게요!",
        normal: "알겠어요! 오늘은 **평소 강도**로 진행할게요 👍",
        tired:  "피곤하시군요 😊 오늘은 **강도 70%**로 가볍게 진행할게요!"
      }

      intro = condition_messages[condition]
      suggested_focus = suggest_today_focus

      success_response(
        message: "#{intro}\n\n오늘은 어떤 운동을 하고 싶으세요?\n\n🏋️ 추천 부위: **#{suggested_focus[:focus]}**\n⏱️ 예상 시간: #{suggested_focus[:duration]}분\n\n\"#{suggested_focus[:focus]} 운동 해줘\" 라고 말씀해주세요!",
        intent: "CONDITION_ACKNOWLEDGED",
        data: {
          condition: condition.to_s,
          intensity: intensity,
          suggested_focus: suggested_focus[:focus],
          suggestions: []
        }
      )
    end

    def handle_submit_feedback(input)
      feedback_text = input["feedback_text"]
      feedback_type = input["feedback_type"]&.to_sym || :specific

      return error_response("피드백 내용을 알려주세요.") if feedback_text.blank?

      store_workout_feedback(feedback_type, feedback_text)

      responses = {
        just_right: {
          message: "좋아요! 👍 현재 강도가 딱 맞는 것 같네요.\n\n다음 운동에도 비슷한 강도로 진행할게요. 꾸준히 하시면 2주 후에는 자연스럽게 강도를 올릴 수 있을 거예요! 💪",
          adjustment: 0
        },
        too_easy: {
          message: "알겠어요! 💪 다음 운동부터 **강도를 올릴게요**.\n\n세트 수나 중량을 조금씩 늘려서 더 도전적인 루틴을 만들어드릴게요!",
          adjustment: 0.1
        },
        too_hard: {
          message: "알겠어요! 😊 다음 운동은 **강도를 낮춰서** 진행할게요.\n\n무리하지 않는 게 중요해요. 폼을 잘 유지하면서 점진적으로 늘려가요!",
          adjustment: -0.1
        },
        specific: {
          message: "피드백 감사합니다! 🙏\n\n\"#{feedback_text}\" - 다음 루틴에 반영할게요!",
          adjustment: 0
        }
      }

      response_data = responses[feedback_type] || responses[:specific]

      lines = [
        response_data[:message],
        "",
        "---",
        "",
        "내일 또 운동하러 오세요! 채팅창에 들어오시면 오늘의 루틴을 준비해드릴게요 🔥"
      ]

      success_response(
        message: lines.join("\n"),
        intent: "FEEDBACK_RECEIVED",
        data: {
          feedback_type: feedback_type.to_s,
          feedback_text: feedback_text,
          intensity_adjustment: response_data[:adjustment],
          suggestions: []
        }
      )
    end

    def store_workout_feedback(feedback_type, feedback_text = nil)
      profile = user.user_profile
      return unless profile

      feedback_type_sym = feedback_type.to_s.to_sym
      factors = profile.fitness_factors || {}

      feedbacks = factors["workout_feedbacks"] || []
      feedbacks << {
        date: Date.current.to_s,
        type: feedback_type_sym.to_s,
        text: feedback_text,
        recorded_at: Time.current.iso8601
      }
      feedbacks = feedbacks.last(30)

      adjustment = factors["intensity_adjustment"] || 0.0
      case feedback_type_sym
      when :too_easy then adjustment = [ adjustment + 0.05, 0.3 ].min
      when :too_hard then adjustment = [ adjustment - 0.05, -0.3 ].max
      end

      factors["workout_feedbacks"]    = feedbacks
      factors["intensity_adjustment"] = adjustment
      factors["last_feedback_at"]     = Time.current.iso8601

      profile.update!(fitness_factors: factors)
    end

    def handle_explain_long_term_plan(input)
      profile = user.user_profile

      unless profile&.onboarding_completed_at
        return error_response("먼저 상담을 완료해주세요. 그래야 맞춤 운동 계획을 세울 수 있어요!")
      end

      consultation_data = profile.fitness_factors&.dig("collected_data") || {}
      long_term_plan = build_long_term_plan(profile, consultation_data)

      program = user.active_training_program
      if program
        long_term_plan[:current_week]       = program.current_week
        long_term_plan[:total_weeks]        = program.total_weeks
        long_term_plan[:current_phase]      = program.current_phase
        long_term_plan[:program_name]       = program.name
        long_term_plan[:progress_percentage] = program.progress_percentage
      end

      detail_level = input["detail_level"] || "detailed"

      prompt = <<~PROMPT
        사용자의 장기 운동 계획을 #{detail_level == 'brief' ? '간단히' : '자세히'} 설명해주세요.

        ## 사용자 정보
        - 이름: #{user.name || '회원'}
        - 레벨: #{profile.numeric_level || 1} (#{tier_korean(profile.tier || 'beginner')})
        - 목표: #{profile.fitness_goal || '건강'}
        - 운동 빈도: #{consultation_data['frequency'] || '주 3회'}
        - 운동 환경: #{consultation_data['environment'] || '헬스장'}
        - 부상/주의사항: #{consultation_data['injuries'] || '없음'}
        - 집중 부위: #{consultation_data['focus_areas'] || '전체'}

        ## 주간 스플릿
        #{long_term_plan[:weekly_split]}

        ## 훈련 전략
        #{long_term_plan[:description]}

        ## 점진적 과부하 전략
        #{long_term_plan[:progression_strategy]}

        ## 예상 타임라인
        #{long_term_plan[:estimated_timeline]}

        ## 현재 진행 상황
        - 프로그램: #{long_term_plan[:program_name] || '미설정'}
        - 현재 주차: #{long_term_plan[:current_week] || '?'}/#{long_term_plan[:total_weeks] || '?'}주
        - 현재 페이즈: #{long_term_plan[:current_phase] || '미설정'}
        - 진행률: #{long_term_plan[:progress_percentage] || 0}%

        ## 응답 규칙
        1. 사용자 정보 기반 맞춤 계획 설명
        2. 주간 스케줄 구체적으로 안내 (요일별 운동 부위)
        3. 목표 달성을 위한 전략 설명
        4. 점진적 과부하 방법 안내
        5. 예상 결과 시점 안내
        6. 친근하고 격려하는 톤
        7. 이모지 적절히 사용
      PROMPT

      response = AiTrainer::LlmGateway.chat(
        prompt: prompt,
        task: :explain_plan,
        system: "당신은 친근하면서도 전문적인 피트니스 AI 트레이너입니다. 한국어로 응답하세요."
      )

      message = response[:success] ? response[:content] : format_long_term_plan_message(long_term_plan, profile)

      success_response(
        message: message,
        intent: "EXPLAIN_LONG_TERM_PLAN",
        data: {
          long_term_plan: long_term_plan,
          user_profile: {
            level: profile.numeric_level || 1,
            tier: profile.tier || "beginner",
            goal: profile.fitness_goal
          },
          suggestions: []
        }
      )
    end
  end
end
