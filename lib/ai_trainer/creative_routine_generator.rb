# frozen_string_literal: true

require_relative "constants"
require_relative "llm_gateway"

module AiTrainer
  # Creative routine generator using RAG + LLM
  # Uses semantic search to find relevant knowledge and generates personalized routines
  class CreativeRoutineGenerator
    include Constants

    # Cache key for tracking recently used knowledge
    RECENT_KNOWLEDGE_KEY = "routine_generator:recent_knowledge:%{user_id}"
    RECENT_KNOWLEDGE_EXPIRY = 7.days

    def initialize(user:, day_of_week: nil)
      @user = user
      @level = user.user_profile&.numeric_level || 1
      @day_of_week = day_of_week || Time.current.wday
      @day_of_week = 1 if @day_of_week == 0
      @day_of_week = 5 if @day_of_week > 5
      @condition = nil
      @preferences = {}
      @goal = nil
      @target_muscles = []
    end

    def with_condition(condition)
      @condition = condition
      self
    end

    def with_preferences(preferences)
      @preferences = preferences || {}
      self
    end

    # Set user's training goal (e.g., "등근육 키우고 싶음", "체중 감량")
    def with_goal(goal)
      @goal = goal
      @target_muscles = extract_target_muscles(goal) if goal.present?
      self
    end

    def generate
      # 1. Gather user context
      user_context = build_user_context

      # 2. Get exercise pool from all programs (뼈대)
      exercise_pool = build_exercise_pool

      # 3. Search RAG for relevant knowledge (살)
      knowledge = search_relevant_knowledge

      # 4. Track used knowledge to avoid repetition
      track_used_knowledge(knowledge)

      # 5. Build prompt for LLM with exercise pool
      prompt = build_generation_prompt(user_context, exercise_pool, knowledge)

      # 6. Call LLM to generate routine
      response = LlmGateway.chat(
        prompt: prompt,
        task: :routine_generation,
        system: system_prompt
      )

      # 7. Parse and validate response
      if response[:success]
        result = parse_routine_response(response[:content])
        result[:knowledge_sources] = knowledge[:sources]
        result[:exercise_pool_used] = exercise_pool[:summary]
        result
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
        goal: @goal,
        target_muscles: @target_muscles,
        recent_exercises: extract_recent_exercises(recent_workouts),
        equipment_available: profile&.available_equipment || %w[barbell dumbbell cable machine],
        workout_duration: profile&.preferred_duration || 60,
        weak_points: profile&.weak_points || [],
        goals: profile&.fitness_goals || []
      }
    end

    # Build exercise pool from all programs (뼈대)
    def build_exercise_pool
      target_muscles = determine_target_muscles
      all_exercises = []
      sources_used = []

      target_muscles.each do |muscle|
        pool = WorkoutPrograms.get_exercise_pool(
          level: @level,
          target_muscle: muscle,
          limit_per_program: 4
        )
        all_exercises.concat(pool)
        sources_used.concat(pool.map { |e| e[:program] }.compact.uniq)
      end

      # Group by muscle for organized presentation
      grouped = all_exercises.group_by { |e| e[:target] }

      {
        exercises: all_exercises,
        by_muscle: grouped,
        sources: sources_used.uniq,
        summary: "#{all_exercises.size}개 운동 (#{sources_used.uniq.join(', ')})"
      }
    end

    # Determine which muscles to target today
    def determine_target_muscles
      return @target_muscles if @target_muscles.any?

      # Use WEEKLY_STRUCTURE to determine today's focus
      day_structure = Constants::WEEKLY_STRUCTURE[@day_of_week]
      return ["전신"] unless day_structure

      case day_structure[:fitness_factor]
      when /상체/
        %w[가슴 등 어깨]
      when /하체/
        %w[하체]
      when /당기기/
        %w[등 이두]
      when /밀기/
        %w[가슴 어깨 삼두]
      else
        %w[가슴 등 하체] # 전신
      end
    end

    def extract_recent_exercises(workouts)
      workouts.flat_map do |session|
        session.workout_routine&.routine_exercises&.pluck(:exercise_name) || []
      end.uniq.first(10)
    end

    def day_name(day)
      %w[일 월 화 수 목 금 토][day] + "요일"
    end

    # Extract target muscles from user's goal text
    def extract_target_muscles(goal)
      muscle_keywords = {
        "등" => %w[등 back 광배 승모 lat],
        "가슴" => %w[가슴 chest 흉근 대흉근 pec],
        "어깨" => %w[어깨 shoulder 삼각근 deltoid],
        "팔" => %w[팔 arm 이두 삼두 bicep tricep],
        "하체" => %w[하체 leg 다리 허벅지 대퇴 quadricep hamstring],
        "코어" => %w[코어 core 복근 abs 복부],
        "전신" => %w[전신 full body 전체]
      }

      goal_lower = goal.downcase
      matched_muscles = []

      muscle_keywords.each do |muscle, keywords|
        matched_muscles << muscle if keywords.any? { |kw| goal_lower.include?(kw) }
      end

      matched_muscles.presence || ["전신"]
    end

    # Improved knowledge search with semantic search and goal-based filtering
    def search_relevant_knowledge
      recently_used_ids = get_recently_used_knowledge_ids
      sources = []

      # Build search query based on goal and context
      search_query = build_search_query

      # 1. Try semantic search first (if embeddings available)
      program_knowledge = search_with_embeddings(
        query: search_query,
        knowledge_type: "routine_design",
        exclude_ids: recently_used_ids,
        limit: 5
      )

      exercise_knowledge = search_with_embeddings(
        query: search_query,
        knowledge_type: "exercise_technique",
        exclude_ids: recently_used_ids,
        limit: 5
      )

      # Track sources
      sources += program_knowledge.map { |k| { id: k[:id], video_id: k[:video_id], type: "routine_design" } }
      sources += exercise_knowledge.map { |k| { id: k[:id], video_id: k[:video_id], type: "exercise_technique" } }

      {
        programs: program_knowledge.map { |k| [k[:content], k[:summary]] },
        exercises: exercise_knowledge.map { |k| [k[:content], k[:summary], k[:exercise_name]] },
        sources: sources
      }
    rescue StandardError => e
      Rails.logger.warn("Knowledge search failed: #{e.message}")
      { programs: [], exercises: [], sources: [] }
    end

    # Build search query based on user goal and context
    def build_search_query
      parts = []

      # Add goal if present
      parts << @goal if @goal.present?

      # Add target muscles
      parts << "#{@target_muscles.join(' ')} 운동" if @target_muscles.any?

      # Add level context
      tier = Constants.tier_for_level(@level)
      parts << "#{tier} 루틴"

      # Add fitness factor for the day
      fitness_factor = Constants::WEEKLY_STRUCTURE[@day_of_week][:fitness_factor]
      parts << fitness_factor if fitness_factor.present?

      parts.join(" ")
    end

    # Search using embeddings (semantic search) with fallback to keyword search
    def search_with_embeddings(query:, knowledge_type:, exclude_ids:, limit:)
      chunks = []

      # Try semantic search if embeddings are available
      if EmbeddingService.pgvector_available? && EmbeddingService.configured?
        query_embedding = EmbeddingService.generate_query_embedding(query)

        if query_embedding.present?
          chunks = FitnessKnowledgeChunk
            .where(knowledge_type: knowledge_type)
            .where.not(embedding: nil)
            .where.not(id: exclude_ids)
            .for_user_level(@level)
            .nearest_neighbors(:embedding, query_embedding, distance: "cosine")
            .limit(limit)
            .select(:id, :content, :summary, :exercise_name, :youtube_video_id)

          chunks = chunks.map do |c|
            {
              id: c.id,
              content: c.content,
              summary: c.summary,
              exercise_name: c.exercise_name,
              video_id: c.youtube_video_id
            }
          end
        end
      end

      # Fallback to keyword search if semantic search returns nothing
      if chunks.empty?
        chunks = keyword_search(
          query: query,
          knowledge_type: knowledge_type,
          exclude_ids: exclude_ids,
          limit: limit
        )
      end

      chunks
    end

    # Keyword-based search as fallback
    def keyword_search(query:, knowledge_type:, exclude_ids:, limit:)
      # Extract keywords from query
      keywords = query.split(/\s+/).reject { |w| w.length < 2 }

      scope = FitnessKnowledgeChunk
        .where(knowledge_type: knowledge_type)
        .where.not(id: exclude_ids)
        .for_user_level(@level)

      # Filter by target muscles if present
      if @target_muscles.any? && knowledge_type == "exercise_technique"
        muscle_conditions = @target_muscles.map { |m| "muscle_group ILIKE ? OR exercise_name ILIKE ? OR content ILIKE ?" }
        muscle_values = @target_muscles.flat_map { |m| ["%#{m}%", "%#{m}%", "%#{m}%"] }
        scope = scope.where(muscle_conditions.join(" OR "), *muscle_values)
      end

      # Search by keywords in content/summary
      if keywords.any?
        keyword_conditions = keywords.map { "content ILIKE ? OR summary ILIKE ?" }
        keyword_values = keywords.flat_map { |kw| ["%#{kw}%", "%#{kw}%"] }
        scope = scope.where(keyword_conditions.join(" OR "), *keyword_values)
      end

      # Order by relevance (prioritize matches in summary) and add some randomness
      scope
        .order(Arel.sql("RANDOM()"))
        .limit(limit)
        .select(:id, :content, :summary, :exercise_name, :youtube_video_id)
        .map do |c|
          {
            id: c.id,
            content: c.content,
            summary: c.summary,
            exercise_name: c.exercise_name,
            video_id: c.youtube_video_id
          }
        end
    end

    # Get IDs of recently used knowledge for this user
    def get_recently_used_knowledge_ids
      cache_key = RECENT_KNOWLEDGE_KEY % { user_id: @user.id }
      Rails.cache.read(cache_key) || []
    end

    # Track used knowledge to avoid repetition
    def track_used_knowledge(knowledge)
      return if knowledge[:sources].blank?

      cache_key = RECENT_KNOWLEDGE_KEY % { user_id: @user.id }
      existing_ids = Rails.cache.read(cache_key) || []

      new_ids = knowledge[:sources].map { |s| s[:id] }
      updated_ids = (existing_ids + new_ids).uniq.last(50) # Keep last 50 used

      Rails.cache.write(cache_key, updated_ids, expires_in: RECENT_KNOWLEDGE_EXPIRY)
    end

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

      # User context
      prompt_parts << <<~USER_CONTEXT
        ## 사용자 정보
        - 레벨: #{context[:level]}/8 (#{context[:tier]})
        - 오늘: #{context[:day_name]}
        - 체력 요인: #{context[:fitness_factor]}
        - 운동 시간: #{context[:workout_duration]}분
        - 사용 가능 장비: #{context[:equipment_available].join(", ")}
      USER_CONTEXT

      # User goal (important!)
      if context[:goal].present?
        prompt_parts << <<~GOAL
          ## 🎯 사용자 목표 (중요!)
          "#{context[:goal]}"
          → 타겟 근육: #{context[:target_muscles].join(", ")}
          → 이 목표에 맞는 운동을 우선적으로 포함하세요!
        GOAL
      end

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

      # Exercise pool from programs (뼈대 - skeleton)
      if exercise_pool[:exercises].any?
        prompt_parts << <<~POOL
          ## 📋 운동 풀 (기본 운동 목록 - 이 중에서 선택하여 구성)
          출처: #{exercise_pool[:sources].join(", ")}

        POOL

        # Group by muscle for better organization
        exercise_pool[:by_muscle].each do |muscle, exercises|
          prompt_parts << "### #{muscle}"
          exercises.first(5).each do |ex|
            details = []
            details << "세트: #{ex[:sets]}" if ex[:sets]
            details << "횟수: #{ex[:reps]}" if ex[:reps]
            details << "BPM: #{ex[:bpm]}" if ex[:bpm]
            details << "ROM: #{ex[:rom]}" if ex[:rom]

            prompt_parts << "- **#{ex[:name]}** (#{details.join(', ')})"
            prompt_parts << "  - #{ex[:how_to].to_s.truncate(100)}" if ex[:how_to].present?
          end
          prompt_parts << ""
        end

        prompt_parts << <<~POOL_GUIDE
          > 위 운동 풀에서 선택하되, 필요시 변형하거나 다른 운동을 추가해도 됩니다.
          > 세트/횟수/휴식은 사용자 레벨과 컨디션에 맞게 조절하세요.
        POOL_GUIDE
      end

      # Program knowledge from RAG (살 - flesh)
      if knowledge[:programs].any?
        prompt_parts << "\n## 📚 참고할 프로그램 패턴 (그대로 복사하지 말고 참고만)"
        knowledge[:programs].each do |content, summary|
          prompt_parts << "- #{summary}: #{content.to_s.truncate(200)}"
        end
      end

      # Exercise knowledge from RAG (tips)
      if knowledge[:exercises].any?
        prompt_parts << "\n## 💡 운동 지식 (팁으로 활용)"
        knowledge[:exercises].each do |content, summary, exercise_name|
          prompt_parts << "- #{exercise_name || summary}: #{content.to_s.truncate(150)}"
        end
      end

      prompt_parts << <<~REQUEST

        ## 요청
        위 정보를 바탕으로 오늘의 맞춤 운동 루틴을 창의적으로 설계해주세요.

        **구성 원칙:**
        1. 운동 풀에서 주요 운동을 선택 (기본 뼈대)
        2. RAG 지식을 참고하여 수행 팁과 주의사항 추가 (살)
        3. 사용자 레벨/컨디션/목표에 맞게 개인화 (맞춤)
        #{context[:goal].present? ? "\n특히 '#{context[:goal]}' 목표에 맞는 운동을 중심으로 구성하세요." : ""}

        4-6개의 운동으로 구성하고, JSON 형식으로만 응답하세요.
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
        creative: false,
        goal: @goal
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
