# frozen_string_literal: true

require_relative "constants"
require_relative "creative_routine/prompt_builder"
require_relative "creative_routine/response_parser"
require_relative "shared/exercise_finder"
require_relative "shared/muscle_group_mapper"
require_relative "shared/time_based_exercise"
require_relative "shared/fallback_routine_builder"

module AiTrainer
  # Creative routine generator using RAG + LLM
  # Uses semantic search to find relevant knowledge and generates personalized routines
  class CreativeRoutineGenerator
    include Constants
    include CreativeRoutine::PromptBuilder
    include CreativeRoutine::ResponseParser
    include Shared::MuscleGroupMapper
    include Shared::TimeBasedExercise
    include Shared::FallbackRoutineBuilder

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

      day_structure = Constants::WEEKLY_STRUCTURE[@day_of_week]
      return [ "전신" ] unless day_structure

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
        %w[가슴 등 하체]
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

    # Knowledge search with semantic search and goal-based filtering
    def search_relevant_knowledge
      recently_used_ids = get_recently_used_knowledge_ids
      sources = []

      search_query = build_search_query

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

      sources += program_knowledge.map { |k| { id: k[:id], video_id: k[:video_id], type: "routine_design" } }
      sources += exercise_knowledge.map { |k| { id: k[:id], video_id: k[:video_id], type: "exercise_technique" } }

      {
        programs: program_knowledge.map { |k| [ k[:content], k[:summary] ] },
        exercises: exercise_knowledge.map { |k| [ k[:content], k[:summary], k[:exercise_name] ] },
        sources: sources
      }
    rescue StandardError => e
      Rails.logger.warn("Knowledge search failed: #{e.message}")
      { programs: [], exercises: [], sources: [] }
    end

    def build_search_query
      [
        (@goal if @goal.present?),
        ("#{@target_muscles.join(' ')} 운동" if @target_muscles.any?),
        "#{Constants.tier_for_level(@level)} 루틴",
        Constants::WEEKLY_STRUCTURE[@day_of_week][:fitness_factor]
      ].compact.join(" ")
    end

    def search_with_embeddings(query:, knowledge_type:, exclude_ids:, limit:)
      chunks = []

      if EmbeddingService.pgvector_available? && EmbeddingService.configured?
        embedding = EmbeddingService.generate_query_embedding(query)
        if embedding.present?
          rows = FitnessKnowledgeChunk
            .where(knowledge_type: knowledge_type).where.not(embedding: nil)
            .where.not(id: exclude_ids).for_user_level(@level)
            .nearest_neighbors(:embedding, embedding, distance: "cosine")
            .limit(limit).select(:id, :content, :summary, :exercise_name, :youtube_video_id)
          chunks = rows.map { |c| { id: c.id, content: c.content, summary: c.summary, exercise_name: c.exercise_name, video_id: c.youtube_video_id } }
        end
      end

      chunks.any? ? chunks : keyword_search(query: query, knowledge_type: knowledge_type, exclude_ids: exclude_ids, limit: limit)
    end

    def keyword_search(query:, knowledge_type:, exclude_ids:, limit:)
      keywords = query.split(/\s+/).reject { |w| w.length < 2 }

      scope = FitnessKnowledgeChunk
        .where(knowledge_type: knowledge_type)
        .where.not(id: exclude_ids)
        .for_user_level(@level)

      if @target_muscles.any? && knowledge_type == "exercise_technique"
        muscle_conditions = @target_muscles.map { "muscle_group ILIKE ? OR exercise_name ILIKE ? OR content ILIKE ?" }
        muscle_values = @target_muscles.flat_map { |m| [ "%#{m}%", "%#{m}%", "%#{m}%" ] }
        scope = scope.where(muscle_conditions.join(" OR "), *muscle_values)
      end

      if keywords.any?
        keyword_conditions = keywords.map { "content ILIKE ? OR summary ILIKE ?" }
        keyword_values = keywords.flat_map { |kw| [ "%#{kw}%", "%#{kw}%" ] }
        scope = scope.where(keyword_conditions.join(" OR "), *keyword_values)
      end

      scope
        .order(Arel.sql("RANDOM()"))
        .limit(limit)
        .select(:id, :content, :summary, :exercise_name, :youtube_video_id)
        .map do |c|
          { id: c.id, content: c.content, summary: c.summary, exercise_name: c.exercise_name, video_id: c.youtube_video_id }
        end
    end

    def get_recently_used_knowledge_ids
      cache_key = RECENT_KNOWLEDGE_KEY % { user_id: @user.id }
      Rails.cache.read(cache_key) || []
    end

    def track_used_knowledge(knowledge)
      return if knowledge[:sources].blank?

      cache_key = RECENT_KNOWLEDGE_KEY % { user_id: @user.id }
      existing_ids = Rails.cache.read(cache_key) || []
      new_ids = knowledge[:sources].map { |s| s[:id] }
      updated_ids = (existing_ids + new_ids).uniq.last(50)
      Rails.cache.write(cache_key, updated_ids, expires_in: RECENT_KNOWLEDGE_EXPIRY)
    end

    def fallback_routine
      {
        routine_id: "RT-FALLBACK-#{Time.current.to_i}",
        generated_at: Time.current.iso8601,
        user_level: @level,
        tier: Constants.tier_for_level(@level),
        day_of_week: @day_of_week,
        training_type: "general",
        exercises: default_exercises_basic,
        estimated_duration_minutes: 45,
        notes: [ "기본 루틴입니다. 컨디션에 맞게 조절하세요." ],
        creative: false,
        goal: @goal
      }
    end
  end
end
