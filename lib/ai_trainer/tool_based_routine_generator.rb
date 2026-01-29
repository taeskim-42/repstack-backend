# frozen_string_literal: true

require_relative "constants"
require_relative "llm_gateway"
require_relative "workout_programs"

module AiTrainer
  # Tool-based routine generator using LLM Tool Use
  # LLM autonomously searches exercises and adjusts training variables
  class ToolBasedRoutineGenerator
    include Constants

    # Training variable guidelines by level
    VARIABLE_GUIDELINES = {
      beginner: { # Level 1-2
        sets_per_exercise: 2..3,
        reps_range: 10..15,
        rpe_range: 5..7,
        rest_seconds: 90..120,
        total_sets: 12..16,
        exercises_count: 4..5,
        tempo: "2-0-2", # controlled
        # 추가 변인들
        rom: "full", # 풀 ROM으로 동작 범위 익히기
        weekly_frequency: "2-3회/부위", # 주당 부위별 빈도
        progression: "주당 2.5% 또는 1-2회 증가", # 선형 점진
        weight_guide: "맨몸 또는 가벼운 무게 (RPE 5-7 유지)",
        notes: "폼 학습 우선, 가벼운 무게로 동작 익히기"
      },
      intermediate: { # Level 3-5
        sets_per_exercise: 3..4,
        reps_range: 8..12,
        rpe_range: 7..8,
        rest_seconds: 60..90,
        total_sets: 16..20,
        exercises_count: 5..6,
        tempo: "2-1-2", # with pause
        # 추가 변인들
        rom: "full_with_stretch", # 풀 ROM + 스트레치 포지션 강조
        weekly_frequency: "2회/부위", # 주당 부위별 빈도
        progression: "주당 2.5-5% 증가, 4주마다 디로드",
        weight_guide: "1RM의 65-75% 또는 RPE 7-8 기준",
        notes: "점진적 과부하, 마인드-머슬 커넥션"
      },
      advanced: { # Level 6-8
        sets_per_exercise: 4..5,
        reps_range: 6..10,
        rpe_range: 8..9,
        rest_seconds: 60..120,
        total_sets: 20..25,
        exercises_count: 5..7,
        tempo: "3-1-2", # slow negative
        # 추가 변인들
        rom: "varied", # 풀/파셜 ROM 혼용 (테크닉별)
        weekly_frequency: "2회/부위 (고빈도) 또는 1회/부위 (고볼륨)",
        progression: "비선형 주기화, 3주 증가 + 1주 디로드",
        weight_guide: "1RM의 75-85% 또는 RPE 8-9 기준",
        notes: "고강도 테크닉, 볼륨 주기화"
      }
    }.freeze

    # Condition modifiers
    CONDITION_MODIFIERS = {
      low_energy: { volume_modifier: 0.7, intensity_modifier: 0.8, note: "볼륨/강도 감소" },
      moderate: { volume_modifier: 1.0, intensity_modifier: 1.0, note: "기본 유지" },
      high_energy: { volume_modifier: 1.1, intensity_modifier: 1.0, note: "볼륨 약간 증가 가능" }
    }.freeze

    def initialize(user:, day_of_week: nil)
      @user = user
      @level = user.user_profile&.numeric_level || 1
      @day_of_week = day_of_week || Time.current.wday
      @day_of_week = 1 if @day_of_week == 0
      @day_of_week = 5 if @day_of_week > 5
      @condition = nil
      @goal = nil
      @tool_calls = [] # Track tool usage for debugging
    end

    def with_condition(condition)
      @condition = condition
      self
    end

    def with_goal(goal)
      @goal = goal
      self
    end

    def generate
      # 1. Build context for LLM
      context = build_context

      # 2. First LLM call with tools
      response = call_llm_with_tools(context)

      # 3. Handle tool calls in a loop until done
      max_iterations = 5
      iteration = 0

      while response[:tool_use] && iteration < max_iterations
        iteration += 1

        # Execute the tool
        tool_result = execute_tool(response[:tool_use])
        @tool_calls << { tool: response[:tool_use][:name], input: response[:tool_use][:input], result_preview: tool_result.to_s.truncate(200) }

        # Continue conversation with tool result
        response = continue_with_tool_result(context, response, tool_result)
      end

      # 4. Parse final response
      if response[:success] && response[:content]
        result = parse_routine_response(response[:content])
        result[:tool_calls] = @tool_calls
        result[:generation_method] = "tool_based"
        result
      else
        fallback_routine
      end
    rescue StandardError => e
      Rails.logger.error("ToolBasedRoutineGenerator error: #{e.message}\n#{e.backtrace.first(5).join("\n")}")
      fallback_routine
    end

    private

    def build_context
      profile = @user.user_profile
      tier = level_to_tier(@level)

      {
        user: {
          level: @level,
          tier: tier,
          tier_korean: tier_korean(tier),
          equipment: %w[barbell dumbbell cable machine bodyweight],
          duration_minutes: 60,
          weak_points: [],
          goals: [profile&.fitness_goal].compact
        },
        today: {
          day_of_week: @day_of_week,
          day_name: %w[일 월 화 수 목 금 토][@day_of_week] + "요일"
        },
        # 컨디션 텍스트 그대로 전달 - LLM이 해석
        condition_text: extract_condition_text,
        goal: @goal,
        variables: VARIABLE_GUIDELINES[tier]
      }
    end

    # 컨디션 정보를 텍스트로 추출 (LLM이 해석하도록)
    def extract_condition_text
      return nil unless @condition

      # 문자열이면 그대로
      return @condition if @condition.is_a?(String)

      # 해시면 notes 또는 조합
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

    def level_to_tier(level)
      case level
      when 1..2 then :beginner
      when 3..5 then :intermediate
      else :advanced
      end
    end

    def tier_korean(tier)
      { beginner: "초급", intermediate: "중급", advanced: "고급" }[tier]
    end

    def assess_condition_state
      return :moderate unless @condition

      energy = @condition[:energy_level] || 3
      sleep = @condition[:sleep_quality] || 3
      avg = (energy + sleep) / 2.0

      if avg <= 2
        :low_energy
      elsif avg >= 4
        :high_energy
      else
        :moderate
      end
    end

    def call_llm_with_tools(context)
      LlmGateway.chat(
        prompt: build_initial_prompt(context),
        task: :routine_generation,
        system: system_prompt,
        tools: available_tools
      )
    end

    def continue_with_tool_result(context, previous_response, tool_result)
      # Build messages array for multi-turn conversation
      messages = [
        { role: "user", content: build_initial_prompt(context) },
        {
          role: "assistant",
          content: [
            { type: "tool_use", id: previous_response[:tool_use][:id], name: previous_response[:tool_use][:name], input: previous_response[:tool_use][:input] }
          ]
        },
        {
          role: "user",
          content: [
            { type: "tool_result", tool_use_id: previous_response[:tool_use][:id], content: tool_result.to_json }
          ]
        }
      ]

      LlmGateway.chat(
        prompt: "", # Empty because we're using messages
        task: :routine_generation,
        system: system_prompt,
        messages: messages,
        tools: available_tools
      )
    end

    def available_tools
      [
        {
          name: "search_exercises",
          description: "근육 부위별 운동을 검색합니다. 3개 프로그램(초중고급, 심현도, 김성환)에서 추출된 운동 풀에서 검색합니다.",
          input_schema: {
            type: "object",
            properties: {
              muscle: {
                type: "string",
                description: "타겟 근육 (가슴, 등, 어깨, 하체, 팔, 코어, 전신)"
              },
              movement_type: {
                type: "string",
                description: "동작 유형 (선택사항): compound(복합), isolation(고립), push(밀기), pull(당기기)",
                enum: %w[compound isolation push pull]
              },
              limit: {
                type: "integer",
                description: "반환할 최대 운동 수 (기본 10)"
              }
            },
            required: ["muscle"]
          }
        },
        {
          name: "get_training_variables",
          description: "사용자 레벨과 컨디션에 맞는 훈련 변인 가이드라인을 조회합니다.",
          input_schema: {
            type: "object",
            properties: {
              include_condition_adjustment: {
                type: "boolean",
                description: "컨디션에 따른 조정값 포함 여부"
              }
            },
            required: []
          }
        },
        {
          name: "get_program_pattern",
          description: "특정 프로그램의 훈련 패턴/철학을 조회합니다.",
          input_schema: {
            type: "object",
            properties: {
              program: {
                type: "string",
                description: "프로그램 이름",
                enum: %w[심현도 김성환 초중고급]
              }
            },
            required: ["program"]
          }
        },
        {
          name: "get_rag_knowledge",
          description: "유튜브 영상에서 추출한 운동 지식을 검색합니다. 운동 팁, 자세 교정, 프로그램 설계 등의 정보를 얻을 수 있습니다.",
          input_schema: {
            type: "object",
            properties: {
              query: {
                type: "string",
                description: "검색 쿼리 (예: '벤치프레스 자세', '등 운동 팁')"
              },
              knowledge_type: {
                type: "string",
                description: "지식 유형",
                enum: %w[exercise_technique routine_design nutrition recovery]
              },
              limit: {
                type: "integer",
                description: "반환할 최대 결과 수 (기본 5)"
              }
            },
            required: ["query"]
          }
        }
      ]
    end

    def execute_tool(tool_use)
      case tool_use[:name]
      when "search_exercises"
        search_exercises(tool_use[:input])
      when "get_training_variables"
        get_training_variables(tool_use[:input])
      when "get_program_pattern"
        get_program_pattern(tool_use[:input])
      when "get_rag_knowledge"
        get_rag_knowledge(tool_use[:input])
      else
        { error: "Unknown tool: #{tool_use[:name]}" }
      end
    end

    # Tool implementations

    def search_exercises(input)
      muscle = input["muscle"] || input[:muscle]
      limit = input["limit"] || input[:limit] || 10

      exercises = WorkoutPrograms.get_exercise_pool(
        level: @level,
        target_muscle: muscle,
        limit_per_program: (limit / 3.0).ceil
      )

      # Filter by movement type if specified
      movement_type = input["movement_type"] || input[:movement_type]
      if movement_type
        exercises = filter_by_movement_type(exercises, movement_type)
      end

      {
        muscle: muscle,
        level: @level,
        exercises: exercises.first(limit).map do |ex|
          {
            name: ex[:name],
            target: ex[:target],
            sets: ex[:sets],
            reps: ex[:reps],
            bpm: ex[:bpm],
            rom: ex[:rom],
            how_to: ex[:how_to]&.truncate(150),
            source: ex[:program]
          }
        end,
        total_found: exercises.size
      }
    end

    def filter_by_movement_type(exercises, movement_type)
      compound_keywords = %w[스쿼트 데드리프트 벤치프레스 로우 프레스 풀업 친업 딥스 런지]
      isolation_keywords = %w[컬 익스텐션 플라이 레이즈 킥백 크런치]
      push_keywords = %w[프레스 푸시 딥스 플라이 레이즈 익스텐션]
      pull_keywords = %w[로우 풀 컬 친업 풀업 데드리프트]

      exercises.select do |ex|
        name = ex[:name].to_s.downcase
        case movement_type
        when "compound"
          compound_keywords.any? { |kw| name.include?(kw) }
        when "isolation"
          isolation_keywords.any? { |kw| name.include?(kw) }
        when "push"
          push_keywords.any? { |kw| name.include?(kw) }
        when "pull"
          pull_keywords.any? { |kw| name.include?(kw) }
        else
          true
        end
      end
    end

    def get_training_variables(input)
      tier = level_to_tier(@level)
      variables = VARIABLE_GUIDELINES[tier].dup

      result = {
        level: @level,
        tier: tier,
        tier_korean: tier_korean(tier),
        guidelines: {
          sets_per_exercise: "#{variables[:sets_per_exercise].min}-#{variables[:sets_per_exercise].max}세트",
          reps_range: "#{variables[:reps_range].min}-#{variables[:reps_range].max}회",
          rpe_range: "RPE #{variables[:rpe_range].min}-#{variables[:rpe_range].max}",
          rest_seconds: "#{variables[:rest_seconds].min}-#{variables[:rest_seconds].max}초",
          total_sets: "총 #{variables[:total_sets].min}-#{variables[:total_sets].max}세트",
          exercises_count: "#{variables[:exercises_count].min}-#{variables[:exercises_count].max}개 운동",
          recommended_tempo: variables[:tempo],
          # 추가 변인들
          rom: variables[:rom],
          weekly_frequency: variables[:weekly_frequency],
          progression: variables[:progression],
          weight_guide: variables[:weight_guide],
          training_notes: variables[:notes]
        }
      }

      include_condition = input["include_condition_adjustment"] || input[:include_condition_adjustment]
      if include_condition && @condition
        condition_text = extract_condition_text
        result[:condition_info] = {
          user_stated: condition_text,
          recommendation: "사용자 컨디션에 따라 볼륨/강도 조절 필요"
        }
      end

      result
    end

    def get_program_pattern(input)
      program = input["program"] || input[:program]

      patterns = {
        "심현도" => {
          name: "심현도 무분할 프로그램",
          philosophy: "BPM(템포)과 ROM(가동범위) 중심의 훈련. 무게보다 근육 자극 품질 우선.",
          key_principles: [
            "느린 네거티브(3-4초)로 근육 긴장 시간 증가",
            "풀 ROM으로 최대 스트레치",
            "레벨별 체계적인 무게 기준 (키-100 기반)",
            "무분할로 매일 전신 자극"
          ],
          typical_tempo: "3-0-2 또는 4-0-2",
          volume_approach: "중간 볼륨, 높은 빈도"
        },
        "김성환" => {
          name: "김성환 근비대 프로그램",
          philosophy: "분할 훈련으로 각 부위 집중 볼륨. 점진적 과부하 중시.",
          key_principles: [
            "4분할 또는 5분할로 부위별 집중",
            "복합운동 먼저, 고립운동 마무리",
            "고볼륨 (부위당 15-20세트)",
            "주기화를 통한 디로드"
          ],
          typical_tempo: "2-1-2",
          volume_approach: "고볼륨, 낮은 빈도(주 1-2회/부위)"
        },
        "초중고급" => {
          name: "레벨별 기본 프로그램",
          philosophy: "사용자 레벨에 맞는 점진적 난이도 상승. 기초부터 탄탄하게.",
          key_principles: [
            "초급: 기본 동작 학습, 낮은 볼륨",
            "중급: 복합운동 중심, 중간 볼륨",
            "고급: 다양한 테크닉, 높은 볼륨"
          ],
          typical_tempo: "레벨별 상이",
          volume_approach: "레벨별 점진적 증가"
        }
      }

      patterns[program] || { error: "Unknown program: #{program}" }
    end

    def get_rag_knowledge(input)
      query = input["query"] || input[:query]
      knowledge_type = input["knowledge_type"] || input[:knowledge_type] || "exercise_technique"
      limit = input["limit"] || input[:limit] || 5

      # Use embedding search if available
      chunks = search_knowledge_chunks(query, knowledge_type, limit)

      {
        query: query,
        knowledge_type: knowledge_type,
        results: chunks.map do |chunk|
          {
            content: chunk[:content]&.truncate(300),
            summary: chunk[:summary],
            exercise_name: chunk[:exercise_name],
            source_video: chunk[:video_id]
          }
        end,
        total_found: chunks.size
      }
    end

    def search_knowledge_chunks(query, knowledge_type, limit)
      return [] unless defined?(FitnessKnowledgeChunk)

      # Try semantic search first
      if defined?(EmbeddingService) && EmbeddingService.pgvector_available? && EmbeddingService.configured?
        query_embedding = EmbeddingService.generate_query_embedding(query)

        if query_embedding.present?
          return FitnessKnowledgeChunk
            .where(knowledge_type: knowledge_type)
            .where.not(embedding: nil)
            .for_user_level(@level)
            .nearest_neighbors(:embedding, query_embedding, distance: "cosine")
            .limit(limit)
            .map do |c|
              {
                content: c.content,
                summary: c.summary,
                exercise_name: c.exercise_name,
                video_id: c.youtube_video_id
              }
            end
        end
      end

      # Fallback to keyword search
      FitnessKnowledgeChunk
        .where(knowledge_type: knowledge_type)
        .where("content ILIKE ? OR summary ILIKE ?", "%#{query}%", "%#{query}%")
        .for_user_level(@level)
        .limit(limit)
        .map do |c|
          {
            content: c.content,
            summary: c.summary,
            exercise_name: c.exercise_name,
            video_id: c.youtube_video_id
          }
        end
    rescue StandardError => e
      Rails.logger.warn("RAG search failed: #{e.message}")
      []
    end

    def system_prompt
      <<~SYSTEM
        당신은 전문 피트니스 트레이너입니다. 사용자에게 맞춤형 운동 루틴을 창의적으로 설계합니다.

        ## 중요: 오늘 하루 운동만 생성
        - 여러 주 또는 여러 요일의 프로그램을 만들지 마세요
        - **오늘 하루** 수행할 운동 루틴 1개만 생성하세요
        - 4-6개의 운동으로 구성된 단일 세션을 만드세요

        ## 도구 사용 가이드
        1. search_exercises: 타겟 근육에 맞는 운동을 검색하세요
        2. get_training_variables: 사용자 레벨에 맞는 모든 훈련 변인 가이드라인을 확인하세요
        3. get_program_pattern: 프로그램 철학을 참고하여 믹스하세요 (심현도의 템포 + 김성환의 볼륨 등)
        4. get_rag_knowledge: 운동 팁이나 자세 관련 지식이 필요하면 검색하세요

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

        ## 응답 형식
        도구를 사용하여 정보를 수집한 후, 최종 루틴을 아래 JSON 형식으로 응답하세요:
        ```json
        {
          "routine_name": "루틴 이름",
          "training_focus": "훈련 포커스",
          "estimated_duration": 45,
          "exercises": [
            {
              "name": "운동명",
              "target_muscle": "타겟 근육",
              "sets": 4,
              "reps": 10,
              "rpe": 8,
              "tempo": "3-1-2",
              "rom": "full",
              "rest_seconds": 90,
              "weight_guide": "무게 선택 기준",
              "instructions": "수행 팁",
              "source_program": "참고 프로그램"
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

        1. 먼저 get_training_variables로 이 사용자에게 맞는 훈련 변인 가이드라인을 확인하세요
        2. search_exercises로 목표에 맞는 운동들을 검색하세요
        3. 필요하면 get_program_pattern으로 프로그램 철학을 참고하세요
        4. 운동 팁이 필요하면 get_rag_knowledge로 검색하세요
        5. 수집한 정보를 바탕으로 창의적인 루틴을 JSON으로 생성하세요
      REQUEST

      parts.join("\n")
    end

    def parse_routine_response(content)
      json_str = extract_json(content)
      data = JSON.parse(json_str)

      exercises = data["exercises"].map.with_index(1) do |ex, idx|
        {
          order: idx,
          exercise_id: "EX-#{idx}-#{SecureRandom.hex(4)}",
          exercise_name: ex["name"],
          target_muscle: ex["target_muscle"],
          sets: ex["sets"],
          reps: ex["reps"],
          rpe: ex["rpe"],
          tempo: ex["tempo"],
          rom: ex["rom"],                    # 가동범위
          rest_seconds: ex["rest_seconds"] || 60,
          weight_guide: ex["weight_guide"],  # 무게 가이드
          instructions: ex["instructions"],
          source_program: ex["source_program"],
          rest_type: "time_based"
        }
      end

      day_names = %w[일 월 화 수 목 금 토]
      day_names_en = %w[sunday monday tuesday wednesday thursday friday saturday]

      {
        routine_id: "RT-#{@level}-#{Time.current.to_i}-#{SecureRandom.hex(4)}",
        generated_at: Time.current.iso8601,
        user_level: @level,
        tier: level_to_tier(@level),
        day_of_week: day_names_en[@day_of_week] || "wednesday",
        day_korean: "#{day_names[@day_of_week]}요일",
        fitness_factor: "strength",
        fitness_factor_korean: data["training_focus"] || "근력 훈련",
        condition: { status: "good", message: "오늘도 화이팅!" },
        training_type: data["training_focus"],
        exercises: exercises,
        estimated_duration_minutes: data["estimated_duration"] || 45,
        # 추가 변인들
        weekly_frequency: data["weekly_frequency"],
        progression: data["progression"],
        variable_adjustments: data["variable_adjustments"],
        notes: [data["coach_message"]].compact,
        creative: true,
        goal: @goal
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
      day_names = %w[일 월 화 수 목 금 토]
      day_names_en = %w[sunday monday tuesday wednesday thursday friday saturday]

      {
        routine_id: "RT-FALLBACK-#{Time.current.to_i}",
        generated_at: Time.current.iso8601,
        user_level: @level,
        tier: level_to_tier(@level),
        day_of_week: day_names_en[@day_of_week] || "wednesday",
        day_korean: "#{day_names[@day_of_week]}요일",
        fitness_factor: "general",
        fitness_factor_korean: "기본 훈련",
        condition: { status: "good", message: "오늘도 화이팅!" },
        training_type: "general",
        exercises: default_exercises,
        estimated_duration_minutes: 45,
        notes: ["기본 루틴입니다. 컨디션에 맞게 조절하세요."],
        creative: false,
        goal: @goal,
        generation_method: "fallback"
      }
    end

    def default_exercises
      [
        { order: 1, exercise_name: "스쿼트", target_muscle: "하체", sets: 3, reps: 10, rest_seconds: 90 },
        { order: 2, exercise_name: "벤치프레스", target_muscle: "가슴", sets: 3, reps: 10, rest_seconds: 90 },
        { order: 3, exercise_name: "바벨로우", target_muscle: "등", sets: 3, reps: 10, rest_seconds: 90 },
        { order: 4, exercise_name: "플랭크", target_muscle: "코어", sets: 3, reps: 30, rest_seconds: 45 }
      ]
    end
  end
end
