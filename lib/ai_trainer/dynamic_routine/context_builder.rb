# frozen_string_literal: true

module AiTrainer
  module DynamicRoutine
    # Builds the AI generation prompt and exercise pool query methods.
    # Depends on host class providing: @level, @day_of_week, @condition_score,
    # @adjustment, @condition_inputs, @goal, @target_muscles, @recent_feedbacks, @preferences
    module ContextBuilder
      # Build the full prompt for Claude
      def build_generation_prompt(training_focus, exercises)
        <<~PROMPT
          너는 전문 피트니스 트레이너야. 사용자에게 맞는 오늘의 운동 루틴을 생성해줘.

          ## 사용자 정보
          - 레벨: #{@level} (#{Constants.tier_for_level(@level)})
          - 오늘 컨디션: #{@condition_score.round(1)}/5 (#{@adjustment[:korean]})
          #{condition_details}
          #{goal_section}

          ## 오늘의 훈련 목표
          #{training_focus_description(training_focus)}

          ## 사용 가능한 운동 목록
          #{exercises_list(exercises)}

          ## 최근 피드백
          #{recent_feedback_summary}

          ## 생성 규칙
          1. 운동 개수: #{@preferences[:exercises_per_workout]} 운동
          2. 예상 소요 시간: #{@preferences[:workout_duration_minutes]}분
          3. 컨디션에 따른 조정: 볼륨 x#{@adjustment[:volume_modifier]}, 강도 x#{@adjustment[:intensity_modifier]}
          4. 가동범위(ROM): full(기본), medium(긴장유지), short(고반복/타바타)
          5. 세트/횟수는 훈련 방법에 맞게 설정

          ## 응답 형식 (JSON)
          다음 형식의 JSON으로 응답해줘:
          ```json
          {
            "exercises": [
              {
                "exercise_id": "운동 ID (위 목록에서)",
                "exercise_name": "운동명",
                "sets": 3,
                "reps": 10,
                "target_total_reps": null,
                "weight_description": "무게 설명 (예: 10회 가능한 무게)",
                "bpm": 30,
                "rom": "full",
                "work_seconds": null,
                "rest_seconds": 60,
                "training_method": "standard",
                "instructions": "이 운동을 어떻게 수행할지 상세 안내"
              }
            ],
            "warmup_suggestion": "워밍업 제안",
            "cooldown_suggestion": "쿨다운 제안",
            "coach_note": "오늘 운동에 대한 코치 코멘트"
          }
          ```

          중요:
          - exercise_id는 반드시 위 운동 목록에 있는 ID를 사용
          - 타바타는 sets 대신 work_seconds: 20, rest_seconds: 10 사용
          - 채우기는 sets: null, target_total_reps: 100 같은 형식
          - JSON만 응답 (설명 없이)
        PROMPT
      end

      # Fetch exercises from DB based on training focus
      def fetch_available_exercises(training_focus)
        exercises = Exercise.active.for_level(@level)

        if @preferences[:available_equipment].present?
          exercises = exercises.where("equipment && ARRAY[?]::varchar[]", @preferences[:available_equipment])
        end

        exercises = exercises.where(muscle_group: training_focus[:muscle_groups]) if training_focus[:muscle_groups].present?

        if training_focus[:fitness_factor].present? && training_focus[:fitness_factor] != :general
          exercises = exercises.for_fitness_factor(training_focus[:fitness_factor])
        end

        exercises = exercises.where.not(english_name: @preferences[:avoid_exercises]) if @preferences[:avoid_exercises].present?

        if @preferences[:focus_muscles].present?
          focus = exercises.where(muscle_group: @preferences[:focus_muscles])
          others = exercises.where.not(muscle_group: @preferences[:focus_muscles])
          exercises = focus + others
        end

        exercises.to_a
      end

      private

      def condition_details
        return "- 컨디션 입력 없음" if @condition_inputs.empty?

        @condition_inputs.filter_map do |key, value|
          config = Constants::CONDITION_INPUTS[key.to_sym]
          "- #{config[:korean]}: #{value}/5" if config
        end.join("\n")
      end

      def goal_section
        return "" unless @goal.present?

        section = "## 사용자 목표\n- #{@goal}"
        section += "\n- 타겟 근육: #{@target_muscles.join(', ')}" if @target_muscles.present?
        section
      end

      def training_focus_description(focus)
        case focus[:type]
        when :fitness_factor
          factor_info = Constants::FITNESS_FACTORS[focus[:fitness_factor]]
          method_info = DynamicRoutineConfig::TRAINING_METHODS[focus[:training_method]]
          "- 체력요인: #{focus[:fitness_factor_korean]} (#{factor_info[:description]})\n" \
          "- 훈련 방법: #{method_info[:korean]} - #{method_info[:description]}\n" \
          "- 전신 운동 (근육군 제한 없음)"
        when :full_body
          "- 전신 운동 (무분할)\n- 모든 주요 근육군을 골고루 자극"
        when :split
          "- #{DynamicRoutineConfig::SPLIT_TYPES[focus[:split_type]][:korean]}\n- 오늘 타겟: #{focus[:muscle_groups].join(', ')}"
        end
      end

      def exercises_list(exercises)
        exercises.map do |ex|
          methods = []
          methods << "BPM" if ex.bpm_compatible
          methods << "타바타" if ex.tabata_compatible
          methods << "드랍세트" if ex.dropset_compatible
          "- ID: #{ex.id}, #{ex.name} (#{ex.muscle_group}, 난이도: #{ex.difficulty}, 방법: #{methods.join('/')})"
        end.join("\n")
      end

      def recent_feedback_summary
        return "- 최근 피드백 없음" if @recent_feedbacks.empty?

        @recent_feedbacks.first(5).map do |fb|
          "- #{fb[:created_at]&.to_date}: #{fb[:difficulty]} 난이도, #{fb[:energy]} 에너지, 만족도 #{fb[:enjoyment]}/5"
        end.join("\n")
      end
    end
  end
end
