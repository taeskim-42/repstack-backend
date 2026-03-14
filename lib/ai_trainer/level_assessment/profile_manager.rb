# frozen_string_literal: true

module AiTrainer
  module LevelAssessment
    # Handles DB profile CRUD, state persistence, routine creation, and completion messages.
    # All methods access instance variables via the host class.
    module ProfileManager
      include AssessmentConstants

      # ── State persistence ────────────────────────────────────────────────────

      def get_assessment_state
        profile.fitness_factors["assessment_state"] || STATES[:initial]
      end

      def get_collected_data
        profile.fitness_factors["collected_data"] || {}
      end

      def save_assessment_state(state, collected_data)
        current_factors = profile.fitness_factors || {}
        profile.update!(
          fitness_factors: current_factors.merge(
            "assessment_state" => state,
            "collected_data" => collected_data
          )
        )
      end

      # ── Profile updates ──────────────────────────────────────────────────────

      def update_profile_with_assessment(assessment)
        return unless assessment

        experience_level = assessment["experience_level"] || "beginner"
        initial_numeric_level = numeric_level_for(experience_level)

        profile.update!(
          fitness_goal: assessment["fitness_goal"],
          current_level: experience_level,
          numeric_level: initial_numeric_level,
          onboarding_completed_at: Time.current,
          fitness_factors: profile.fitness_factors.merge(
            "onboarding_assessment" => assessment,
            "assessment_state" => STATES[:completed],
            "initial_level_source" => "ai_consultation"
          )
        )
      end

      # Extract profile data already collected during form onboarding
      def extract_form_data
        data = {}

        if profile.current_level.present?
          level_str = profile.current_level.to_s.downcase
          data["experience"] = if %w[beginner intermediate advanced].include?(level_str)
                                 level_str
          elsif profile.numeric_level.present?
                                 level_string_from_numeric(profile.numeric_level.to_i)
          end
        end

        data["goals"]  = profile.fitness_goal if profile.fitness_goal.present?
        data["height"] = profile.height       if profile.height.present?
        data["weight"] = profile.weight       if profile.weight.present?
        data
      end

      # ── Program generation ───────────────────────────────────────────────────

      def generate_initial_routine(_collected_data)
        Rails.logger.info("[LevelAssessmentService] Generating training program for user #{user.id}")

        program_result = ProgramGenerator.generate(user: user)

        if program_result[:success] && program_result[:program].present?
          program = program_result[:program]
          Rails.logger.info("[LevelAssessmentService] Training program generated: #{program.id} (#{program.name})")
          { success: true, program: program, coach_message: program_result[:coach_message] }
        else
          Rails.logger.warn("[LevelAssessmentService] Failed to generate program: #{program_result[:error]}")
          { success: false, error: program_result[:error] }
        end
      rescue => e
        Rails.logger.error("[LevelAssessmentService] Error generating training program: #{e.message}")
        { success: false, error: e.message }
      end

      # ── Completion messages ──────────────────────────────────────────────────

      def build_completion_message_with_routine(base_message, program_result)
        collected = get_collected_data
        goal       = collected["goals"] || profile.fitness_goal || "근력 향상"
        experience = collected["experience"] || "beginner"
        frequency  = collected["frequency"] || "주 3회"

        program       = program_result[:program]
        coach_message = program_result[:coach_message]

        lines = program.present? ? build_program_lines(program, coach_message) : build_fallback_lines(goal, experience, frequency)
        lines << "매일 컨디션과 피드백을 반영해서 **AI가 최적의 루틴을 생성**해드려요! 💪"
        lines << ""
        lines << "---"
        lines << ""
        lines << "오늘의 첫 운동을 시작할까요? 🔥"
        lines.join("\n")
      end

      # Build a friendly message confirming auto-completion when all fields gathered
      def build_auto_complete_message(collected)
        experience = translate_experience(collected["experience"])
        msg  = "완벽해요! 💪\n\n"
        msg += "**파악된 정보:**\n"
        msg += "- 경험: #{experience}\n"
        msg += "- 목표: #{collected['goals']}\n"
        msg += "- 운동 빈도: #{collected['frequency']}\n"
        msg += "- 환경: #{collected['environment']}\n"        if collected["environment"].present?
        msg += "- 부상: #{collected['injuries']}\n"          if collected["injuries"].present? && collected["injuries"] != "없음"
        msg += "- 선호: #{collected['preferences']}\n"       if collected["preferences"].present?
        msg += "\n이 정보를 바탕으로 딱 맞는 루틴을 만들어드릴게요! 🏋️"
        msg
      end

      # Mock completion path (used when LLM is unavailable)
      def complete_assessment(collected)
        experience_level       = collected["experience"] || "intermediate"
        initial_numeric_level  = numeric_level_for(experience_level)

        update_profile_with_assessment({
          "experience_level" => experience_level,
          "fitness_goal"     => collected["goals"],
          "summary"          => build_consultation_summary(collected)
        })

        {
          success: true,
          message: "좋아요! 상담 내용을 바탕으로 딱 맞는 루틴을 만들어드릴게요! 💪",
          is_complete: true,
          assessment: {
            "experience_level"   => experience_level,
            "numeric_level"      => initial_numeric_level,
            "fitness_goal"       => collected["goals"],
            "summary"            => build_consultation_summary(collected),
            "consultation_data"  => collected
          }
        }
      end

      private

      def numeric_level_for(experience_level)
        case experience_level
        when "beginner"     then 1
        when "intermediate" then 3
        when "advanced"     then 5
        else 1
        end
      end

      def level_string_from_numeric(n)
        case n
        when 1..2 then "beginner"
        when 3..5 then "intermediate"
        else "advanced"
        end
      end

      def build_program_lines(program, coach_message)
        lines = []
        workout_days = count_workout_days(program)

        lines << "🎉 **#{program.name}**을 생성했습니다!"
        lines << ""
        lines << "📋 **프로그램 개요**"
        lines << "• 목표: #{program.goal}"
        lines << "• 총 기간: #{program.total_weeks}주"
        lines << "• 주 #{workout_days > 0 ? workout_days : '?'}회 운동"
        lines << "• 주기화: #{periodization_korean(program.periodization_type)}"
        lines << ""

        if program.weekly_plan.present?
          lines << "📅 **주차별 계획**"
          program.weekly_plan.each do |week_range, info|
            phase = info["phase"] || info[:phase]
            theme = info["theme"] || info[:theme]
            lines << "• #{week_range}주: #{phase} - #{theme}"
          end
          lines << ""
        end

        if program.split_schedule.present?
          lines << "🗓️ **운동 분할**"
          lines << build_split_summary(program.split_schedule)
          lines << ""
        end

        if coach_message.present?
          lines << "💬 #{coach_message}"
          lines << ""
        end

        lines
      end

      def build_fallback_lines(goal, experience, frequency)
        lines = []
        lines << "🎉 **맞춤 운동 프로그램**을 생성했습니다!"
        lines << ""
        lines << "📋 **프로그램 특징**"
        lines << "• 목표: #{goal_korean(goal)}"
        lines << "• 레벨: #{level_korean(experience)} → 점진적 강도 증가"
        lines << ""
        lines
      end

      def count_workout_days(program)
        program.split_schedule&.count { |_, info|
          focus = info["focus"] || info[:focus]
          focus.present? && focus != "휴식"
        } || 0
      end

      def build_split_summary(split_schedule)
        day_names = { "1" => "월", "2" => "화", "3" => "수", "4" => "목", "5" => "금", "6" => "토", "7" => "일" }
        parts = split_schedule.filter_map do |day_num, info|
          focus = info["focus"] || info[:focus]
          next if focus.blank? || focus == "휴식"
          "#{day_names[day_num.to_s] || day_num}: #{focus}"
        end
        parts.any? ? parts.join(" / ") : "전신 운동"
      end

      def periodization_korean(type)
        case type.to_s.downcase
        when "linear"     then "선형 주기화 (점진적 증가)"
        when "undulating" then "비선형 주기화 (물결형)"
        when "block"      then "블록 주기화"
        else "점진적 과부하"
        end
      end

      def goal_korean(goal)
        case goal.to_s.downcase
        when /근비대|muscle|hypertrophy/ then "근비대 (근육량 증가)"
        when /strength|근력/            then "근력 향상"
        when /다이어트|fat|loss|체중/    then "체지방 감소"
        when /체력|endurance|지구력/     then "체력/지구력 향상"
        else "균형잡힌 체력 향상"
        end
      end

      def level_korean(experience)
        case experience.to_s.downcase
        when /beginner|초보/    then "입문자"
        when /intermediate|중급/ then "중급자"
        when /advanced|고급/     then "고급자"
        else "입문자"
        end
      end
    end
  end
end
