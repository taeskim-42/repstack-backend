# frozen_string_literal: true

require_relative "constants"
require_relative "dynamic_routine_config"
require_relative "llm_gateway"

module AiTrainer
  # Generates workout routines dynamically using AI
  # Instead of fixed programs, it combines:
  # - Exercise pool (from DB)
  # - Split rules
  # - Training methods
  # - User context (level, condition, feedback)
  class DynamicRoutineGenerator
    include Constants
    include DynamicRoutineConfig

    attr_reader :user, :level, :day_of_week, :condition_score, :adjustment,
                :condition_inputs, :recent_feedbacks, :preferences

    def initialize(user:, day_of_week: nil)
      @user = user
      @level = user.user_profile&.numeric_level || user.user_profile&.level || 1
      @day_of_week = day_of_week || Time.current.wday
      @day_of_week = 1 if @day_of_week == 0 # Sunday -> Monday
      @day_of_week = 5 if @day_of_week > 5 # Weekend -> Friday
      @condition_score = 3.0
      @adjustment = Constants::CONDITION_ADJUSTMENTS[:good]
      @condition_inputs = {}
      @recent_feedbacks = []
      @preferences = default_preferences
    end

    # Set user preferences
    def with_preferences(prefs)
      @preferences = default_preferences.merge(prefs.symbolize_keys)
      self
    end

    # Set condition from user input
    def with_condition(condition_inputs)
      @condition_inputs = condition_inputs
      @condition_score = Constants.calculate_condition_score(condition_inputs)
      @adjustment = Constants.adjustment_for_condition_score(@condition_score)
      self
    end

    # Set recent feedbacks for personalization
    def with_feedbacks(feedbacks)
      @recent_feedbacks = feedbacks || []
      self
    end

    # Generate a dynamic routine
    def generate
      # 1. Determine today's training focus
      training_focus = determine_training_focus

      # 2. Get available exercises from pool
      available_exercises = fetch_available_exercises(training_focus)

      # 3. Build AI prompt with all context
      prompt = build_generation_prompt(training_focus, available_exercises)

      # 4. Call Claude to generate routine
      ai_response = generate_with_ai(prompt)

      # 5. Parse and validate response
      routine = parse_ai_response(ai_response, available_exercises)

      # 6. Enrich with YouTube knowledge
      enriched_routine = enrich_with_knowledge(routine)

      # 7. Build final response
      build_routine_response(enriched_routine, training_focus)
    rescue StandardError => e
      Rails.logger.error("DynamicRoutineGenerator error: #{e.message}\n#{e.backtrace.first(5).join("\n")}")
      { success: false, error: "루틴 생성 실패: #{e.message}" }
    end

    private

    def default_preferences
      {
        split_type: :fitness_factor_based,
        available_equipment: %w[none shark_rack dumbbell cable machine barbell],
        workout_duration_minutes: 45,
        exercises_per_workout: 4..6,
        preferred_training_methods: [:standard, :bpm, :tabata],
        avoid_exercises: [],
        focus_muscles: []
      }
    end

    # Determine what to train today based on split and day
    def determine_training_focus
      split_type = @preferences[:split_type]
      config = DynamicRoutineConfig::SPLIT_TYPES[split_type]

      case split_type
      when :fitness_factor_based
        day_name = %w[sunday monday tuesday wednesday thursday friday saturday][@day_of_week]
        day_config = config[:schedule][day_name.to_sym]

        {
          type: :fitness_factor,
          fitness_factor: day_config[:factor],
          fitness_factor_korean: day_config[:korean],
          muscle_groups: nil, # All muscles for the fitness factor
          training_method: recommended_method_for_factor(day_config[:factor])
        }
      when :full_body
        {
          type: :full_body,
          fitness_factor: :general,
          muscle_groups: config[:muscle_groups_per_day],
          training_method: :standard
        }
      else
        # For split-based training
        schedule = DynamicRoutineConfig.build_schedule(split_type, @day_of_week)
        {
          type: :split,
          split_type: split_type,
          muscle_groups: schedule,
          training_method: :standard
        }
      end
    end

    def recommended_method_for_factor(factor)
      case factor
      when :strength then :bpm
      when :muscular_endurance then :fill_target
      when :sustainability then :bpm
      when :cardiovascular then :tabata
      when :power then :standard
      else :standard
      end
    end

    # Fetch exercises from DB based on training focus
    def fetch_available_exercises(training_focus)
      exercises = Exercise.active.for_level(@level)

      # Filter by equipment
      if @preferences[:available_equipment].present?
        exercises = exercises.where(
          "equipment && ARRAY[?]::varchar[]",
          @preferences[:available_equipment]
        )
      end

      # Filter by muscle groups if specified
      if training_focus[:muscle_groups].present?
        exercises = exercises.where(muscle_group: training_focus[:muscle_groups])
      end

      # Filter by fitness factor if specified
      if training_focus[:fitness_factor].present? && training_focus[:fitness_factor] != :general
        exercises = exercises.for_fitness_factor(training_focus[:fitness_factor])
      end

      # Exclude avoided exercises
      if @preferences[:avoid_exercises].present?
        exercises = exercises.where.not(english_name: @preferences[:avoid_exercises])
      end

      # Prioritize focus muscles
      if @preferences[:focus_muscles].present?
        focus = exercises.where(muscle_group: @preferences[:focus_muscles])
        others = exercises.where.not(muscle_group: @preferences[:focus_muscles])
        exercises = focus + others
      end

      exercises.to_a
    end

    # Build prompt for Claude
    def build_generation_prompt(training_focus, exercises)
      <<~PROMPT
        너는 전문 피트니스 트레이너야. 사용자에게 맞는 오늘의 운동 루틴을 생성해줘.

        ## 사용자 정보
        - 레벨: #{@level} (#{Constants.tier_for_level(@level)})
        - 오늘 컨디션: #{@condition_score.round(1)}/5 (#{@adjustment[:korean]})
        #{condition_details}

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

    def condition_details
      return "- 컨디션 입력 없음" if @condition_inputs.empty?

      details = @condition_inputs.map do |key, value|
        config = Constants::CONDITION_INPUTS[key.to_sym]
        next unless config

        "- #{config[:korean]}: #{value}/5"
      end.compact

      details.join("\n")
    end

    def training_focus_description(focus)
      case focus[:type]
      when :fitness_factor
        factor_info = Constants::FITNESS_FACTORS[focus[:fitness_factor]]
        method_info = DynamicRoutineConfig::TRAINING_METHODS[focus[:training_method]]

        <<~DESC
          - 체력요인: #{focus[:fitness_factor_korean]} (#{factor_info[:description]})
          - 훈련 방법: #{method_info[:korean]} - #{method_info[:description]}
          - 전신 운동 (근육군 제한 없음)
        DESC
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

    # Call Claude API
    def generate_with_ai(prompt)
      response = LlmGateway.chat(
        prompt: prompt,
        task: :routine_generation
      )

      raise "AI 응답 실패: #{response[:error]}" unless response[:success]

      response[:content]
    end

    # Parse AI response into structured routine
    def parse_ai_response(response, available_exercises)
      # Extract JSON from response
      json_match = response.match(/```json\s*(.*?)\s*```/m) || response.match(/\{.*\}/m)
      raise "AI 응답에서 JSON을 찾을 수 없습니다" unless json_match

      json_str = json_match[1] || json_match[0]
      data = JSON.parse(json_str, symbolize_names: true)

      # Build exercise lookup
      exercise_lookup = available_exercises.index_by(&:id)

      # Map exercises
      exercises = data[:exercises].map.with_index(1) do |ex, order|
        db_exercise = exercise_lookup[ex[:exercise_id].to_i]

        {
          order: order,
          exercise_id: ex[:exercise_id],
          exercise_name: ex[:exercise_name] || db_exercise&.name,
          english_name: db_exercise&.english_name,
          target_muscle: db_exercise&.muscle_group,
          sets: ex[:sets],
          reps: ex[:reps],
          target_total_reps: ex[:target_total_reps],
          weight_description: ex[:weight_description],
          bpm: ex[:bpm],
          range_of_motion: ex[:rom] || "full",
          work_seconds: ex[:work_seconds],
          rest_seconds: ex[:rest_seconds] || 60,
          rest_type: ex[:work_seconds] ? "tabata" : "time_based",
          training_method: ex[:training_method] || "standard",
          instructions: ex[:instructions],
          form_tips: db_exercise&.form_tips,
          common_mistakes: db_exercise&.common_mistakes
        }
      end

      {
        exercises: exercises,
        warmup_suggestion: data[:warmup_suggestion],
        cooldown_suggestion: data[:cooldown_suggestion],
        coach_note: data[:coach_note]
      }
    end

    # Enrich with YouTube knowledge (similar to RoutineGenerator)
    def enrich_with_knowledge(routine)
      return routine unless rag_available?

      exercise_names = routine[:exercises].map { |ex| ex[:english_name] }.compact
      muscle_groups = routine[:exercises].map { |ex| ex[:target_muscle] }.compact.uniq

      begin
        contextual_knowledge = RagSearchService.contextual_search(
          exercises: exercise_names,
          muscle_groups: muscle_groups,
          knowledge_types: %w[exercise_technique form_check],
          difficulty_level: difficulty_for_level(@level),
          limit: 15
        )

        routine[:exercises] = routine[:exercises].map do |ex|
          enrich_exercise(ex, contextual_knowledge)
        end
      rescue StandardError => e
        Rails.logger.warn("Knowledge enrichment failed: #{e.message}")
      end

      routine
    end

    def rag_available?
      defined?(RagSearchService) && defined?(FitnessKnowledgeChunk)
    end

    def difficulty_for_level(level)
      case level
      when 1..2 then "beginner"
      when 3..5 then "intermediate"
      when 6..8 then "advanced"
      else "intermediate"
      end
    end

    def enrich_exercise(exercise, contextual_knowledge)
      target_name = exercise[:english_name]&.downcase
      relevant = contextual_knowledge.select do |k|
        # Exact match for exercise name (handles comma-separated values)
        exercise_names = k[:exercise_name]&.downcase&.split(", ") || []
        exercise_match = exercise_names.include?(target_name) || k[:exercise_name]&.downcase == target_name
        muscle_match = k[:muscle_group]&.downcase == exercise[:target_muscle]&.downcase
        exercise_match || muscle_match
      end

      if relevant.present?
        tips = relevant.first(2).map { |k| k[:summary] }.compact
        sources = relevant.first(2).map do |k|
          next unless k[:source]

          {
            title: k[:source][:video_title],
            url: k[:source][:video_url]
          }
        end.compact

        exercise[:expert_tips] = tips if tips.present?
        exercise[:video_references] = sources if sources.present?
      end

      exercise
    end

    # Build final response
    def build_routine_response(routine, training_focus)
      day_info = Constants::WEEKLY_STRUCTURE[@day_of_week]

      {
        success: true,
        routine_id: generate_routine_id,
        generated_at: Time.current.iso8601,
        generation_type: "dynamic",
        user_level: @level,
        tier: Constants.tier_for_level(@level),
        tier_korean: Constants::LEVELS[@level][:korean_tier],
        day_of_week: @day_of_week,
        day_korean: day_info[:korean],
        training_focus: training_focus,
        condition: {
          score: @condition_score.round(2),
          status: @adjustment[:korean],
          volume_modifier: @adjustment[:volume_modifier],
          intensity_modifier: @adjustment[:intensity_modifier]
        },
        exercises: routine[:exercises],
        warmup_suggestion: routine[:warmup_suggestion],
        cooldown_suggestion: routine[:cooldown_suggestion],
        coach_note: routine[:coach_note],
        estimated_duration_minutes: @preferences[:workout_duration_minutes],
        preferences_used: @preferences.slice(:split_type, :available_equipment)
      }
    end

    def generate_routine_id
      "DRT-#{@level}-D#{@day_of_week}-#{Time.current.to_i}-#{SecureRandom.hex(4)}"
    end
  end
end
