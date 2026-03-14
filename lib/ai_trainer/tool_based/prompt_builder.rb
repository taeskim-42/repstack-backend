# frozen_string_literal: true

module AiTrainer
  module ToolBased
    # Builds prompts for the LLM tool-use routine generation flow.
    # Depends on: @level, @day_of_week, @goal, @condition (from host class)
    module PromptBuilder
      include TrainingData
      def system_prompt
        <<~SYSTEM
          당신은 전문 피트니스 트레이너입니다. 사용자에게 맞춤형 운동 루틴을 창의적으로 설계합니다.

          ## 중요: 오늘 하루 운동만 생성
          - 여러 주 또는 여러 요일의 프로그램을 만들지 마세요
          - **오늘 하루** 수행할 운동 루틴 1개만 생성하세요
          - 4-6개의 운동으로 구성된 단일 세션을 만드세요

          ## ⚠️ 매우 중요: 운동 선택 규칙
          - **반드시 get_routine_data에서 제공된 운동만 사용하세요**
          - 제공되지 않은 운동을 임의로 추가하지 마세요
          - 각 운동의 **id**를 JSON의 **exercise_id** 필드에 반드시 포함하세요
          - **운동 이름은 반드시 한글로 작성하세요** (예: "벤치프레스", "데드리프트", "스쿼트")
          - 영어 운동명(Bench Press, Deadlift) 대신 한글 운동명을 사용하세요
          - **has_video=true인 운동을 우선 선택하세요** (사용자에게 참고 영상 제공 가능)

          ## 최근 운동 기록 활용
          - recent_workouts에 최근 7일간 운동 기록이 포함됨
          - **최근에 한 운동은 피하고 다른 운동을 선택**하여 균형있게 훈련
          - 같은 근육 그룹을 연속으로 훈련하지 않도록 주의

          ## 도구 사용 (⚠️ 1번만 호출!)
          1. get_routine_data 호출 → 모든 운동 + 훈련 변인 한번에 조회
          2. 즉시 JSON 반환

          ❌ 여러 번 도구 호출 금지
          ✅ get_routine_data 1번 → JSON 반환

          ## 루틴 설계 원칙 (9가지 변인 모두 고려)
          1. **운동 순서**: 복합운동 먼저 → 고립운동 마무리
          2. **볼륨**: 레벨에 맞는 총 세트 수
          3. **강도 (RPE)**: 레벨에 맞는 RPE 범위
          4. **템포**: 레벨에 맞는 BPM (예: 3-1-2)
          5. **ROM**: 가동 범위 (full, partial, stretch 등)
          6. **휴식**: 세트 간 휴식 시간
          7. **무게 가이드**: 적절한 무게 선택 기준
          8. **빈도**: 주당 훈련 빈도 안내
          9. **주기화**: 점진적 과부하 방법 안내

          ## 시간 기반 운동 처리
          플랭크, 홀드, 월싯 등 **시간으로 측정하는 운동**은:
          - `is_time_based: true` 설정
          - `work_seconds`: 운동 시간 (초)
          - `reps`: null 또는 생략

          ## 응답 형식
          도구를 사용하여 정보를 수집한 후, 최종 루틴을 아래 JSON 형식으로 응답하세요:
          ```json
          {
            "routine_name": "루틴 이름",
            "training_focus": "훈련 포커스",
            "estimated_duration": 45,
            "exercises": [
              {
                "exercise_id": 123,
                "name": "운동명",
                "target_muscle": "타겟 근육",
                "sets": 4,
                "reps": 10,
                "is_time_based": false,
                "work_seconds": null,
                "rpe": 8,
                "tempo": "3-1-2",
                "rom": "full",
                "rest_seconds": 90,
                "weight_guide": "무게 선택 기준",
                "instructions": "수행 팁",
                "source_program": "참고 프로그램"
              },
              {
                "exercise_id": 456,
                "name": "플랭크",
                "target_muscle": "코어",
                "sets": 3,
                "reps": null,
                "is_time_based": true,
                "work_seconds": 30,
                "rest_seconds": 45,
                "instructions": "코어에 힘을 주고 버티기"
              }
            ],
            "weekly_frequency": "주당 훈련 빈도 안내",
            "progression": "다음 주 목표 (점진적 과부하)",
            "variable_adjustments": "적용된 변인 조절 설명",
            "coach_message": "코치 메시지"
          }
          ```
        SYSTEM
      end

      def build_initial_prompt(context)
        parts = []

        parts << <<~CONTEXT
          ## 사용자 정보
          - 레벨: #{context[:user][:level]}/8 (#{context[:user][:tier_korean]})
          - 사용 가능 장비: #{context[:user][:equipment].join(", ")}
          - 운동 시간: #{context[:user][:duration_minutes]}분
        CONTEXT

        if context[:program].present?
          program = context[:program]
          parts << <<~PROGRAM
            ## 📋 장기 프로그램 정보
            - 프로그램: #{program[:name]}
            - 진행 상황: #{program[:progress]}
            - 현재 페이즈: #{program[:phase]} (#{program[:theme]})
            - 볼륨 조절: #{(program[:volume_modifier] * 100).round}% #{program[:is_deload] ? "(디로드 주간 - 회복 우선)" : ""}
            - 오늘 포커스: #{program[:today_focus] || "전신"}
            #{program[:today_muscles].any? ? "- 타겟 근육: #{program[:today_muscles].join(', ')}" : ""}

            ⚠️ 중요: 위 프로그램 페이즈와 볼륨 조절값을 반드시 반영하세요!
            #{program[:is_deload] ? "🔵 디로드 주간입니다. 볼륨과 강도를 낮추고 회복에 집중하세요." : ""}
          PROGRAM
        end

        if context[:goal].present?
          parts << <<~GOAL
            ## 🎯 오늘의 목표
            "#{context[:goal]}"
          GOAL
        end

        if context[:condition_text].present?
          parts << <<~CONDITION
            ## 오늘 컨디션
            "#{context[:condition_text]}"
            → 이 컨디션에 맞게 볼륨/강도를 조절하세요
          CONDITION
        end

        parts << <<~REQUEST

          ## 요청
          위 정보를 바탕으로 오늘의 맞춤 운동 루틴을 설계해주세요.

          1. 먼저 get_routine_data로 운동과 훈련 변인을 확인하세요
          2. 프로그램 페이즈(적응기/성장기/강화기/디로드)에 맞게 볼륨/강도를 조절하세요
          3. 오늘 포커스 근육을 중심으로 루틴을 구성하세요
          4. 수집한 정보를 바탕으로 창의적인 루틴을 JSON으로 생성하세요
        REQUEST

        parts.join("\n")
      end

      def build_context
        profile = @user.user_profile
        tier = level_to_tier(@level)

        context = {
          user: {
            level: @level,
            tier: tier,
            tier_korean: tier_korean(tier),
            equipment: %w[barbell dumbbell cable machine bodyweight],
            duration_minutes: 60,
            weak_points: [],
            goals: [ profile&.fitness_goal ].compact
          },
          today: {
            day_of_week: @day_of_week,
            day_name: %w[일 월 화 수 목 금 토][@day_of_week] + "요일"
          },
          condition_text: extract_condition_text,
          goal: @goal,
          variables: VARIABLE_GUIDELINES[tier]
        }

        program = @user.active_training_program
        context[:program] = build_program_context(program) if program.present?

        context
      end

      private

      def build_program_context(program)
        today_schedule = program.today_focus(@day_of_week)

        {
          name: program.name,
          total_weeks: program.total_weeks,
          current_week: program.current_week,
          progress: "#{program.current_week}/#{program.total_weeks}주 (#{program.progress_percentage}%)",
          phase: program.current_phase,
          theme: program.current_theme,
          volume_modifier: program.current_volume_modifier,
          is_deload: program.deload_week?,
          periodization: program.periodization_type,
          today_focus: today_schedule&.dig("focus"),
          today_muscles: today_schedule&.dig("muscles") || []
        }
      end

      def extract_condition_text
        return nil unless @condition
        return @condition if @condition.is_a?(String)

        if @condition[:notes].present?
          @condition[:notes]
        elsif @condition[:energy_level] || @condition[:sleep_quality]
          parts = []
          parts << "에너지 #{@condition[:energy_level]}/5" if @condition[:energy_level]
          parts << "수면 #{@condition[:sleep_quality]}/5" if @condition[:sleep_quality]
          parts << "스트레스 #{@condition[:stress_level]}/5" if @condition[:stress_level]
          parts.join(", ")
        end
      end
    end
  end
end
