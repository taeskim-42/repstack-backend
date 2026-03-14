# frozen_string_literal: true

module ChatOnboarding
  module FormHandler
    private

    # ============================================
    # Today's Routine (Post-Onboarding)
    # ============================================

    def wants_today_routine?
      return false if message.blank?

      return false if needs_level_assessment?

      profile = UserProfile.find_by(user_id: user.id)
      Rails.logger.info("[wants_today_routine?] user_id=#{user.id}, onboarding_completed_at=#{profile&.onboarding_completed_at}")
      return false unless profile&.onboarding_completed_at.present?

      routine_count = WorkoutRoutine.where(user_id: user.id).count
      Rails.logger.info("[wants_today_routine?] routine_count=#{routine_count}, message=#{message}")

      routine_count == 0
    end

    def handle_show_today_routine
      program = ensure_training_program

      day_of_week = Time.current.wday
      day_of_week = day_of_week == 0 ? 7 : day_of_week

      result = AiTrainer.generate_routine(
        user: user,
        day_of_week: day_of_week,
        condition_inputs: nil,
        recent_feedbacks: user.workout_feedbacks.order(created_at: :desc).limit(5)
      )

      if result.is_a?(Hash) && result[:success] == false
        return error_response(result[:error] || "루틴 생성에 실패했어요.")
      end

      program_info = if program
        {
          name: program.name,
          current_week: program.current_week,
          total_weeks: program.total_weeks,
          phase: program.current_phase,
          volume_modifier: program.current_volume_modifier
        }
      end

      lines = []
      lines << "오늘의 운동 루틴이에요! 💪"
      lines << ""

      if program_info
        lines << "🗓️ **#{program_info[:name]}** - #{program_info[:current_week]}/#{program_info[:total_weeks]}주차 (#{program_info[:phase]})"
      end

      lines << "📋 **#{result[:day_korean] || '오늘의 운동'}**"
      lines << "⏱️ 예상 시간: #{result[:estimated_duration_minutes] || 45}분"
      lines << ""
      lines << "**운동 목록:**"

      exercises = result[:exercises] || []
      exercises.each_with_index do |ex, idx|
        name = ex[:exercise_name] || ex["exercise_name"] || ex[:name] || ex["name"]
        sets = ex[:sets] || ex["sets"] || 3
        reps = ex[:reps] || ex["reps"] || 10
        lines << "#{idx + 1}. **#{name}** - #{sets}세트 x #{reps}회"
      end

      lines << ""
      lines << "운동을 마치면 **\"운동 끝났어\"** 라고 말씀해주세요!"
      lines << "피드백을 받아 다음 루틴을 최적화해드릴게요 📈"

      success_response(
        message: lines.join("\n"),
        intent: "GENERATE_ROUTINE",
        data: {
          routine: result,
          program: program_info,
          suggestions: [ "운동 시작할게", "운동 끝났어" ]
        }
      )
    end

    # ============================================
    # Welcome Message (First Chat After Onboarding)
    # ============================================

    def needs_welcome_message?
      return false if message.present? && message != "시작" && message != "start"

      profile = user.user_profile
      return false unless profile&.onboarding_completed_at

      recently_onboarded = profile.onboarding_completed_at > 5.minutes.ago
      no_routines_yet = !user.workout_routines.exists?

      recently_onboarded && no_routines_yet
    end

    def handle_welcome_message
      profile = user.user_profile
      tier = profile&.tier || "beginner"
      level = profile&.numeric_level || 1
      goal = profile&.fitness_goal || "건강"

      consultation_data = profile&.fitness_factors&.dig("collected_data") || {}
      long_term_plan = build_long_term_plan(profile, consultation_data)

      prompt = build_welcome_prompt(profile, consultation_data, long_term_plan)

      response = AiTrainer::LlmGateway.chat(
        prompt: prompt,
        task: :welcome_with_plan,
        system: "당신은 친근하면서도 전문적인 피트니스 AI 트레이너입니다. 한국어로 응답하세요."
      )

      welcome_text = if response[:success]
        response[:content]
      else
        default_welcome_with_plan(profile, long_term_plan)
      end

      first_routine = generate_first_routine

      if first_routine && first_routine[:exercises].present?
        routine_message = format_first_routine_message(first_routine)
        full_message = "#{welcome_text}\n\n---\n\n#{routine_message}"

        success_response(
          message: full_message,
          intent: "WELCOME_WITH_ROUTINE",
          data: {
            is_first_chat: true,
            user_profile: { level: level, tier: tier, goal: goal },
            long_term_plan: long_term_plan,
            routine: first_routine,
            suggestions: []
          }
        )
      else
        success_response(
          message: welcome_text,
          intent: "WELCOME",
          data: {
            is_first_chat: true,
            user_profile: { level: level, tier: tier, goal: goal },
            long_term_plan: long_term_plan,
            suggestions: []
          }
        )
      end
    end

    def generate_first_routine
      day_of_week = Time.current.wday
      day_of_week = day_of_week == 0 ? 7 : day_of_week
      day_of_week = [ day_of_week, 5 ].min

      AiTrainer.generate_routine(
        user: user,
        day_of_week: day_of_week,
        condition_inputs: { energy_level: 4, notes: "첫 운동 - 적응 기간" },
        goal: user.user_profile&.fitness_goal
      )
    rescue StandardError => e
      Rails.logger.error("[ChatService] Failed to generate first routine: #{e.message}")
      nil
    end

    def default_welcome_with_plan(profile, long_term_plan)
      name = user.name || "회원"
      goal = profile&.fitness_goal || "건강"
      tier = profile&.tier || "beginner"

      tier_name = tier_korean(tier)
      weekly_split = long_term_plan[:weekly_split]

      "#{name}님, 환영합니다! 🎉\n\n" \
      "상담 내용을 바탕으로 #{name}님만의 운동 계획을 세웠어요.\n\n" \
      "📌 **목표:** #{goal}\n" \
      "📌 **레벨:** #{tier_name}\n" \
      "📌 **주간 스케줄:** #{weekly_split}\n\n" \
      "#{long_term_plan[:description]}\n\n" \
      "잠시만요, 오늘의 맞춤 루틴을 준비할게요... 💪"
    end

    def default_welcome_message(profile)
      name = user.name || "회원"
      goal = profile&.fitness_goal || "건강"

      "#{name}님, 환영합니다! 🎉\n\n" \
      "#{goal} 목표로 함께 운동해봐요. " \
      "\"오늘 루틴 만들어줘\"라고 말씀해주시면 맞춤 운동을 준비해드릴게요! 💪"
    end

    # ============================================
    # Level Assessment (Special Flow)
    # ============================================

    def needs_level_assessment?
      AiTrainer::LevelAssessmentService.needs_assessment?(user)
    end

    def handle_level_assessment
      result = AiTrainer::LevelAssessmentService.assess(user: user, message: message)

      if result[:success]
        intent = result[:is_complete] ? "TRAINING_PROGRAM" : "CONSULTATION"
        suggestions = result[:suggestions].presence || extract_suggestions_from_message(result[:message])

        Rails.logger.info("[handle_level_assessment] intent=#{intent}, suggestions_from_result=#{result[:suggestions].inspect}, final_suggestions=#{suggestions.inspect}")

        clean_message = strip_suggestions_text(result[:message])

        success_response(
          message: clean_message,
          intent: intent,
          data: {
            is_complete: result[:is_complete],
            assessment: result[:assessment],
            suggestions: suggestions
          }
        )
      else
        error_response(result[:error] || "수준 파악에 실패했어요.")
      end
    end

    private

    def build_welcome_prompt(profile, consultation_data, long_term_plan)
      <<~PROMPT
        새로 온보딩을 완료한 사용자에게 장기 운동 계획을 설명하고 첫 루틴을 제안해주세요.

        ## 사용자 정보
        - 이름: #{user.name || '회원'}
        - 레벨: #{profile&.numeric_level || 1} (#{tier_korean(profile&.tier || 'beginner')})
        - 목표: #{profile&.fitness_goal || '건강'}
        - 키: #{profile&.height}cm
        - 체중: #{profile&.weight}kg
        - 운동 빈도: #{consultation_data['frequency'] || '주 3회'}
        - 운동 환경: #{consultation_data['environment'] || '헬스장'}
        - 부상/주의사항: #{consultation_data['injuries'] || '없음'}
        - 집중 부위: #{consultation_data['focus_areas'] || '전체'}

        ## 장기 운동 계획
        #{long_term_plan[:description]}

        ## 주간 스플릿
        #{long_term_plan[:weekly_split]}

        ## 응답 규칙
        1. 환영 인사 (이름 포함)
        2. 상담 내용 바탕으로 맞춤 장기 계획 설명 (주간 스플릿, 목표 달성 전략)
        3. "지금 바로 오늘의 루틴을 만들어드릴게요!" 라고 말하며 루틴 생성 예고
        4. 친근하고 격려하는 톤
        5. 4-6문장 정도로 충분히 설명
        6. 이모지 적절히 사용
        7. **마지막에 반드시** "잠시만요, 오늘의 맞춤 루틴을 준비할게요... 💪" 라고 끝내기
      PROMPT
    end
  end
end
