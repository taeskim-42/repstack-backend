# frozen_string_literal: true

module AiTrainer
  module CreativeRoutine
    # Builds system prompt and user prompt for creative routine generation.
    # Depends on host class providing: @level, @day_of_week, @goal, @target_muscles
    module PromptBuilder
      def system_prompt
        <<~SYSTEM
          당신은 전문 피트니스 트레이너입니다. 사용자에게 맞춤형 운동 루틴을 창의적으로 설계합니다.

          ## 원칙
          1. 제공된 프로그램 지식을 "참고"하되, 그대로 복사하지 않습니다
          2. 사용자의 레벨, 컨디션, 선호도를 반영하여 개인화합니다
          3. 운동 과학에 기반한 합리적인 세트/횟수를 설정합니다
          4. 다양성을 위해 매번 약간씩 다른 루틴을 제안합니다
          5. 사용자의 목표가 있다면 그에 맞는 운동을 우선 배치합니다

          ## 응답 형식
          반드시 아래 JSON 형식으로만 응답하세요:
          ```json
          {
            "routine_name": "루틴 이름",
            "training_focus": "근력/근지구력/심폐지구력 등",
            "estimated_duration": 45,
            "exercises": [
              {
                "name": "운동명",
                "target_muscle": "주 타겟 근육",
                "sets": 3,
                "reps": 10,
                "rest_seconds": 60,
                "instructions": "수행 방법 및 팁",
                "weight_guide": "무게 가이드 (선택)"
              }
            ],
            "warmup_notes": "워밍업 안내",
            "cooldown_notes": "쿨다운 안내",
            "coach_message": "트레이너의 오늘 한마디"
          }
          ```
        SYSTEM
      end

      def build_generation_prompt(context, exercise_pool, knowledge)
        prompt_parts = []

        prompt_parts << build_user_context_section(context)
        prompt_parts << build_goal_section(context) if context[:goal].present?
        prompt_parts << build_condition_section(context) if context[:condition].present?
        prompt_parts << build_recent_exercises_section(context) if context[:recent_exercises].any?
        prompt_parts.concat(build_exercise_pool_sections(exercise_pool)) if exercise_pool[:exercises].any?
        prompt_parts << build_program_knowledge_section(knowledge) if knowledge[:programs].any?
        prompt_parts << build_exercise_knowledge_section(knowledge) if knowledge[:exercises].any?
        prompt_parts << build_request_section(context)

        prompt_parts.join("\n")
      end

      private

      def build_user_context_section(context)
        <<~SECTION
          ## 사용자 정보
          - 레벨: #{context[:level]}/8 (#{context[:tier]})
          - 오늘: #{context[:day_name]}
          - 체력 요인: #{context[:fitness_factor]}
          - 운동 시간: #{context[:workout_duration]}분
          - 사용 가능 장비: #{context[:equipment_available].join(", ")}
        SECTION
      end

      def build_goal_section(context)
        <<~SECTION
          ## 🎯 사용자 목표 (중요!)
          "#{context[:goal]}"
          → 타겟 근육: #{context[:target_muscles].join(", ")}
          → 이 목표에 맞는 운동을 우선적으로 포함하세요!
        SECTION
      end

      def build_condition_section(context)
        cond = context[:condition]
        <<~SECTION
          ## 오늘 컨디션
          - 에너지: #{cond[:energy_level]}/5
          - 스트레스: #{cond[:stress_level]}/5
          - 수면: #{cond[:sleep_quality]}/5
          #{cond[:notes] ? "- 메모: #{cond[:notes]}" : ""}
        SECTION
      end

      def build_recent_exercises_section(context)
        <<~SECTION
          ## 최근 수행한 운동 (중복 피하기)
          #{context[:recent_exercises].join(", ")}
        SECTION
      end

      def build_exercise_pool_sections(exercise_pool)
        parts = []
        parts << <<~POOL
          ## 📋 운동 풀 (기본 운동 목록 - 이 중에서 선택하여 구성)
          출처: #{exercise_pool[:sources].join(", ")}

        POOL

        exercise_pool[:by_muscle].each do |muscle, exercises|
          parts << "### #{muscle}"
          exercises.first(5).each do |ex|
            details = []
            details << "세트: #{ex[:sets]}" if ex[:sets]
            details << "횟수: #{ex[:reps]}" if ex[:reps]
            details << "BPM: #{ex[:bpm]}" if ex[:bpm]
            details << "ROM: #{ex[:rom]}" if ex[:rom]
            parts << "- **#{ex[:name]}** (#{details.join(', ')})"
            parts << "  - #{ex[:how_to].to_s.truncate(100)}" if ex[:how_to].present?
          end
          parts << ""
        end

        parts << <<~POOL_GUIDE
          > 위 운동 풀에서 선택하되, 필요시 변형하거나 다른 운동을 추가해도 됩니다.
          > 세트/횟수/휴식은 사용자 레벨과 컨디션에 맞게 조절하세요.
        POOL_GUIDE

        parts
      end

      def build_program_knowledge_section(knowledge)
        lines = [ "\n## 📚 참고할 프로그램 패턴 (그대로 복사하지 말고 참고만)" ]
        knowledge[:programs].each do |content, summary|
          lines << "- #{summary}: #{content.to_s.truncate(200)}"
        end
        lines.join("\n")
      end

      def build_exercise_knowledge_section(knowledge)
        lines = [ "\n## 💡 운동 지식 (팁으로 활용)" ]
        knowledge[:exercises].each do |content, summary, exercise_name|
          lines << "- #{exercise_name || summary}: #{content.to_s.truncate(150)}"
        end
        lines.join("\n")
      end

      def build_request_section(context)
        <<~REQUEST

          ## 요청
          위 정보를 바탕으로 오늘의 맞춤 운동 루틴을 창의적으로 설계해주세요.

          **구성 원칙:**
          1. 운동 풀에서 주요 운동을 선택 (기본 뼈대)
          2. RAG 지식을 참고하여 수행 팁과 주의사항 추가 (살)
          3. 사용자 레벨/컨디션/목표에 맞게 개인화 (맞춤)
          #{context[:goal].present? ? "\n특히 '#{context[:goal]}' 목표에 맞는 운동을 중심으로 구성하세요." : ""}

          4-6개의 운동으로 구성하고, JSON 형식으로만 응답하세요.
        REQUEST
      end
    end
  end
end
