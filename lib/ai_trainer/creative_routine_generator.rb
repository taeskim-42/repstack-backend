# frozen_string_literal: true

require_relative "constants"
require_relative "llm_gateway"

module AiTrainer
  # Creative routine generator using RAG + LLM
  # Instead of copying hardcoded programs, uses knowledge base to create personalized routines
  class CreativeRoutineGenerator
    include Constants

    def initialize(user:, day_of_week: nil)
      @user = user
      @level = user.user_profile&.numeric_level || 1
      @day_of_week = day_of_week || Time.current.wday
      @day_of_week = 1 if @day_of_week == 0
      @day_of_week = 5 if @day_of_week > 5
      @condition = nil
      @preferences = {}
    end

    def with_condition(condition)
      @condition = condition
      self
    end

    def with_preferences(preferences)
      @preferences = preferences || {}
      self
    end

    def generate
      # 1. Gather user context
      user_context = build_user_context

      # 2. Search RAG for relevant knowledge
      knowledge = search_relevant_knowledge

      # 3. Build prompt for LLM
      prompt = build_generation_prompt(user_context, knowledge)

      # 4. Call LLM to generate routine
      response = LlmGateway.chat(
        prompt: prompt,
        task: :routine_generation,
        system: system_prompt
      )

      # 5. Parse and validate response
      if response[:success]
        parse_routine_response(response[:content])
      else
        fallback_routine
      end
    rescue StandardError => e
      Rails.logger.error("CreativeRoutineGenerator error: #{e.message}\n#{e.backtrace.first(5).join("\n")}")
      fallback_routine
    end

    private

    def build_user_context
      profile = @user.user_profile
      recent_workouts = @user.workout_sessions.completed.order(created_at: :desc).limit(5)

      {
        level: @level,
        tier: Constants.tier_for_level(@level),
        day_of_week: @day_of_week,
        day_name: day_name(@day_of_week),
        fitness_factor: Constants::WEEKLY_STRUCTURE[@day_of_week][:fitness_factor],
        condition: @condition,
        preferences: @preferences,
        recent_exercises: extract_recent_exercises(recent_workouts),
        equipment_available: profile&.available_equipment || %w[barbell dumbbell cable machine],
        workout_duration: profile&.preferred_duration || 60,
        weak_points: profile&.weak_points || [],
        goals: profile&.fitness_goals || []
      }
    end

    def extract_recent_exercises(workouts)
      workouts.flat_map do |session|
        session.workout_routine&.routine_exercises&.pluck(:exercise_name) || []
      end.uniq.first(10)
    end

    def day_name(day)
      %w[일 월 화 수 목 금 토][day] + "요일"
    end

    def search_relevant_knowledge
      fitness_factor = Constants::WEEKLY_STRUCTURE[@day_of_week][:fitness_factor]

      # Search for program templates
      program_knowledge = FitnessKnowledgeChunk
        .where(knowledge_type: "routine_design")
        .for_user_level(@level)
        .limit(5)
        .pluck(:content, :summary)

      # Search for exercise techniques
      exercise_knowledge = FitnessKnowledgeChunk
        .where(knowledge_type: "exercise_technique")
        .for_user_level(@level)
        .order("RANDOM()")
        .limit(5)
        .pluck(:content, :summary, :exercise_name)

      {
        programs: program_knowledge,
        exercises: exercise_knowledge
      }
    rescue StandardError => e
      Rails.logger.warn("Knowledge search failed: #{e.message}")
      { programs: [], exercises: [] }
    end

    def system_prompt
      <<~SYSTEM
        당신은 전문 피트니스 트레이너입니다. 사용자에게 맞춤형 운동 루틴을 창의적으로 설계합니다.

        ## 원칙
        1. 제공된 프로그램 지식을 "참고"하되, 그대로 복사하지 않습니다
        2. 사용자의 레벨, 컨디션, 선호도를 반영하여 개인화합니다
        3. 운동 과학에 기반한 합리적인 세트/횟수를 설정합니다
        4. 다양성을 위해 매번 약간씩 다른 루틴을 제안합니다

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

    def build_generation_prompt(context, knowledge)
      prompt_parts = []

      # User context
      prompt_parts << <<~USER_CONTEXT
        ## 사용자 정보
        - 레벨: #{context[:level]}/8 (#{context[:tier]})
        - 오늘: #{context[:day_name]}
        - 체력 요인: #{context[:fitness_factor]}
        - 운동 시간: #{context[:workout_duration]}분
        - 사용 가능 장비: #{context[:equipment_available].join(", ")}
      USER_CONTEXT

      # Condition if provided
      if context[:condition].present?
        prompt_parts << <<~CONDITION
          ## 오늘 컨디션
          - 에너지: #{context[:condition][:energy_level]}/5
          - 스트레스: #{context[:condition][:stress_level]}/5
          - 수면: #{context[:condition][:sleep_quality]}/5
          #{context[:condition][:notes] ? "- 메모: #{context[:condition][:notes]}" : ""}
        CONDITION
      end

      # Recent exercises (to avoid repetition)
      if context[:recent_exercises].any?
        prompt_parts << <<~RECENT
          ## 최근 수행한 운동 (중복 피하기)
          #{context[:recent_exercises].join(", ")}
        RECENT
      end

      # Program knowledge from RAG
      if knowledge[:programs].any?
        prompt_parts << "## 참고할 프로그램 패턴 (그대로 복사하지 말고 참고만)"
        knowledge[:programs].each do |content, summary|
          prompt_parts << "- #{summary}: #{content.truncate(200)}"
        end
      end

      # Exercise knowledge from RAG
      if knowledge[:exercises].any?
        prompt_parts << "\n## 운동 지식 (팁으로 활용)"
        knowledge[:exercises].each do |content, summary, exercise_name|
          prompt_parts << "- #{exercise_name || summary}: #{content.truncate(150)}"
        end
      end

      prompt_parts << <<~REQUEST

        ## 요청
        위 정보를 바탕으로 오늘의 맞춤 운동 루틴을 창의적으로 설계해주세요.
        4-6개의 운동으로 구성하고, 사용자 레벨과 컨디션에 맞게 조절하세요.
        JSON 형식으로만 응답하세요.
      REQUEST

      prompt_parts.join("\n")
    end

    def parse_routine_response(content)
      # Extract JSON from response
      json_str = extract_json(content)
      data = JSON.parse(json_str)

      # Build routine response
      exercises = data["exercises"].map.with_index(1) do |ex, idx|
        {
          order: idx,
          exercise_id: "EX-#{idx}-#{SecureRandom.hex(4)}",
          exercise_name: ex["name"],
          target_muscle: ex["target_muscle"],
          sets: ex["sets"],
          reps: ex["reps"],
          rest_seconds: ex["rest_seconds"] || 60,
          instructions: ex["instructions"],
          weight_description: ex["weight_guide"],
          rest_type: "time_based"
        }
      end

      {
        routine_id: "RT-#{@level}-#{Time.current.to_i}-#{SecureRandom.hex(4)}",
        generated_at: Time.current.iso8601,
        user_level: @level,
        tier: Constants.tier_for_level(@level),
        day_of_week: @day_of_week,
        training_type: data["training_focus"],
        exercises: exercises,
        estimated_duration_minutes: data["estimated_duration"] || 45,
        notes: [
          data["warmup_notes"],
          data["cooldown_notes"],
          data["coach_message"]
        ].compact,
        creative: true  # Flag to indicate this was creatively generated
      }
    rescue JSON::ParserError => e
      Rails.logger.error("Failed to parse routine JSON: #{e.message}")
      fallback_routine
    end

    def extract_json(text)
      if text =~ /```(?:json)?\s*(\{.*?\})\s*```/m
        Regexp.last_match(1)
      elsif text.include?("{")
        start_idx = text.index("{")
        end_idx = text.rindex("}")
        text[start_idx..end_idx] if start_idx && end_idx
      else
        text
      end
    end

    def fallback_routine
      # Simple fallback if LLM fails
      {
        routine_id: "RT-FALLBACK-#{Time.current.to_i}",
        generated_at: Time.current.iso8601,
        user_level: @level,
        tier: Constants.tier_for_level(@level),
        day_of_week: @day_of_week,
        training_type: "general",
        exercises: default_exercises,
        estimated_duration_minutes: 45,
        notes: ["기본 루틴입니다. 컨디션에 맞게 조절하세요."],
        creative: false
      }
    end

    def default_exercises
      [
        { order: 1, exercise_name: "푸시업", target_muscle: "가슴", sets: 3, reps: 10, rest_seconds: 60 },
        { order: 2, exercise_name: "스쿼트", target_muscle: "하체", sets: 3, reps: 10, rest_seconds: 60 },
        { order: 3, exercise_name: "플랭크", target_muscle: "코어", sets: 3, reps: 30, rest_seconds: 45 }
      ]
    end
  end
end
