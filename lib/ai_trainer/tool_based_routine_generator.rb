# frozen_string_literal: true

require_relative "constants"
require_relative "llm_gateway"
require_relative "workout_programs"
require_relative "exercise_name_normalizer"

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

    # Split programs by level
    # 초급: 전신 운동 (주 3회)
    # 중급: 상하체 분할 (주 4회) 또는 PPL (주 3-6회)
    # 고급: PPL 또는 4-5분할
    SPLIT_PROGRAMS = {
      beginner: {
        name: "전신 운동",
        description: "모든 주요 근육을 매 세션에 훈련",
        schedule: {
          1 => { focus: "전신", muscles: %w[legs chest back shoulders core] },  # 월
          2 => { focus: "휴식", muscles: [] },                                    # 화
          3 => { focus: "전신", muscles: %w[legs chest back shoulders core] },  # 수
          4 => { focus: "휴식", muscles: [] },                                    # 목
          5 => { focus: "전신", muscles: %w[legs chest back shoulders core] }   # 금
        }
      },
      intermediate: {
        name: "상하체 분할",
        description: "상체와 하체를 번갈아 훈련",
        schedule: {
          1 => { focus: "상체", muscles: %w[chest back shoulders arms] },       # 월
          2 => { focus: "하체", muscles: %w[legs core] },                        # 화
          3 => { focus: "휴식", muscles: [] },                                    # 수
          4 => { focus: "상체", muscles: %w[chest back shoulders arms] },       # 목
          5 => { focus: "하체", muscles: %w[legs core] }                         # 금
        }
      },
      advanced: {
        name: "PPL 분할",
        description: "밀기-당기기-하체 3분할",
        schedule: {
          1 => { focus: "밀기 (Push)", muscles: %w[chest shoulders arms] },     # 월: 가슴, 어깨, 삼두
          2 => { focus: "당기기 (Pull)", muscles: %w[back arms] },               # 화: 등, 이두
          3 => { focus: "하체 (Legs)", muscles: %w[legs core] },                 # 수: 하체, 코어
          4 => { focus: "밀기 (Push)", muscles: %w[chest shoulders arms] },     # 목
          5 => { focus: "당기기 (Pull)", muscles: %w[back arms] }                # 금
        }
      }
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
      Rails.logger.info("[ToolBasedRoutineGenerator] Starting generation with goal: #{@goal.inspect}")

      # 1. Build context for LLM
      context = build_context

      # 2. First LLM call with tools
      Rails.logger.info("[ToolBasedRoutineGenerator] Calling LLM with tools...")
      response = call_llm_with_tools(context)
      Rails.logger.info("[ToolBasedRoutineGenerator] LLM response: success=#{response[:success]}, model=#{response[:model]}, tool_use=#{response[:tool_use].present?}, content_length=#{response[:content]&.length}")

      # 3. Handle tool calls in a loop until done
      max_iterations = 10
      iteration = 0

      while response[:tool_use] && iteration < max_iterations
        iteration += 1
        Rails.logger.info("[ToolBasedRoutineGenerator] Tool call #{iteration}: #{response[:tool_use][:name]}")

        # Execute the tool
        tool_result = execute_tool(response[:tool_use])
        @tool_calls << { tool: response[:tool_use][:name], input: response[:tool_use][:input], result_preview: tool_result.to_s.truncate(200) }

        # Continue conversation with tool result
        response = continue_with_tool_result(context, response, tool_result)
        Rails.logger.info("[ToolBasedRoutineGenerator] After tool result: success=#{response[:success]}, tool_use=#{response[:tool_use].present?}")
      end

      Rails.logger.info("[ToolBasedRoutineGenerator] Final: iterations=#{iteration}, tool_calls=#{@tool_calls.length}")

      # 4. If no content yet, force final response (도구 호출 중단하고 JSON 반환 요청)
      if response[:success] && !response[:content].present? && @tool_calls.any?
        Rails.logger.info("[ToolBasedRoutineGenerator] Forcing final JSON response...")
        response = force_final_response(context)
      end

      # 5. Parse final response
      if response[:success] && response[:content]
        result = parse_routine_response(response[:content])
        result[:tool_calls] = @tool_calls
        result[:generation_method] = "tool_based"
        Rails.logger.info("[ToolBasedRoutineGenerator] Success! exercises=#{result[:exercises]&.length}")
        result
      else
        Rails.logger.warn("[ToolBasedRoutineGenerator] Fallback: success=#{response[:success]}, content=#{response[:content].present?}")
        fallback_routine
      end
    rescue StandardError => e
      Rails.logger.error("ToolBasedRoutineGenerator error: #{e.message}\n#{e.backtrace.first(5).join("\n")}")
      fallback_routine
    end

    private

    def default_rest_for_level
      case @level
      when 1..2 then 90
      when 3..5 then 75
      else 60
      end
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

      # Add training program context if user has active program
      program = @user.active_training_program
      if program.present?
        context[:program] = build_program_context(program)
      end

      context
    end

    # Build context from TrainingProgram for LLM
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

    # Force LLM to return final JSON without more tool calls
    def force_final_response(context)
      force_message = <<~MSG
        도구 호출은 충분합니다. 지금까지 수집한 정보를 바탕으로 **즉시 JSON 형식의 최종 루틴을 반환하세요**.
        더 이상 도구를 호출하지 마세요. 바로 JSON을 출력하세요.
      MSG

      LlmGateway.chat(
        prompt: force_message,
        task: :routine_generation,
        system: system_prompt,
        tools: nil  # No tools - force text response
      )
    end

    def available_tools
      [
        {
          name: "get_routine_data",
          description: "루틴 생성에 필요한 모든 데이터를 한 번에 가져옵니다. 이 도구를 1번만 호출하면 됩니다.",
          input_schema: {
            type: "object",
            properties: {},
            required: []
          }
        }
      ]
    end

    def execute_tool(tool_use)
      case tool_use[:name]
      when "get_routine_data"
        get_routine_data
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

    # Single tool that returns all data needed for routine generation
    def get_routine_data
      tier = level_to_tier(@level)
      variables = VARIABLE_GUIDELINES[tier].dup
      split = SPLIT_PROGRAMS[tier]
      today_schedule = split[:schedule][@day_of_week] || split[:schedule][1]

      # Check if user has active training program
      program = @user.active_training_program
      program_context = nil

      if program.present?
        program_context = build_program_context(program)

        # Override today_schedule with program's split_schedule if available
        program_today = program.today_focus(@day_of_week)
        if program_today.present? && program_today["muscles"].present?
          today_schedule = {
            focus: program_today["focus"],
            muscles: program_today["muscles"]
          }
        end

        # Apply volume modifier from program phase
        volume_mod = program.current_volume_modifier
        if volume_mod != 1.0
          # Adjust total_sets based on volume modifier
          original_min = variables[:total_sets].min
          original_max = variables[:total_sets].max
          variables[:total_sets] = ((original_min * volume_mod).round)..((original_max * volume_mod).round)
        end
      end

      # If user has a specific goal, extract muscles from it (overrides schedule)
      goal_muscles = extract_muscles_from_goal(@goal) if @goal.present?
      Rails.logger.info("[ToolBasedRoutineGenerator] Goal: #{@goal.inspect}, extracted muscles: #{goal_muscles.inspect}")

      # Use goal muscles if specified, otherwise use schedule (from program or default)
      target_muscles = if goal_muscles.present?
        Rails.logger.info("[ToolBasedRoutineGenerator] Using GOAL-based muscles: #{goal_muscles}")
        goal_muscles
      else
        Rails.logger.info("[ToolBasedRoutineGenerator] Using SCHEDULE-based muscles: #{today_schedule[:muscles]}")
        today_schedule[:muscles]
      end

      # Get exercises for target muscles
      exercises_by_muscle = {}

      if target_muscles.empty?
        # 휴식일이면 가벼운 전신 또는 유산소 추천
        %w[core].each do |muscle|
          exercises = Exercise.active.for_level(@level).for_muscle(muscle).order(:difficulty).limit(5)
          exercises_by_muscle[muscle] = exercises.map { |ex| exercise_to_hash(ex) }
        end
      else
        target_muscles.each do |muscle|
          exercises = Exercise.active.for_level(@level).for_muscle(muscle).order(:difficulty).limit(8)
          exercises_by_muscle[muscle] = exercises.map { |ex| exercise_to_hash(ex) }
        end
      end

      # Get recent workout history
      recent_history = get_recent_workout_history

      # Determine focus text
      focus_text = if goal_muscles.present?
        "사용자 요청: #{@goal}"
      else
        today_schedule[:focus]
      end

      result = {
        user_level: @level,
        tier: tier,
        tier_korean: tier_korean(tier),
        split_program: {
          name: split[:name],
          description: split[:description],
          today_focus: focus_text,
          target_muscles: target_muscles,
          user_goal: @goal
        },
        training_variables: {
          sets_per_exercise: "#{variables[:sets_per_exercise].min}-#{variables[:sets_per_exercise].max}",
          reps_range: "#{variables[:reps_range].min}-#{variables[:reps_range].max}",
          rpe_range: "#{variables[:rpe_range].min}-#{variables[:rpe_range].max}",
          rest_seconds: "#{variables[:rest_seconds].min}-#{variables[:rest_seconds].max}",
          tempo: variables[:tempo],
          exercises_count: "#{variables[:exercises_count].min}-#{variables[:exercises_count].max}",
          total_sets: "#{variables[:total_sets].min}-#{variables[:total_sets].max}"
        },
        exercises: exercises_by_muscle,
        recent_workouts: recent_history,
        instructions: build_instructions(focus_text, target_muscles, goal_muscles.present?)
      }

      # Add program context if available
      if program_context.present?
        result[:program_context] = {
          name: program_context[:name],
          current_week: program_context[:current_week],
          total_weeks: program_context[:total_weeks],
          phase: program_context[:phase],
          theme: program_context[:theme],
          volume_modifier: program_context[:volume_modifier],
          is_deload: program_context[:is_deload]
        }
        result[:instructions] += " 현재 #{program_context[:phase]} 페이즈 (볼륨 #{(program_context[:volume_modifier] * 100).round}%)입니다."
        result[:instructions] += " 디로드 주간이므로 볼륨과 강도를 낮추세요." if program_context[:is_deload]
      end

      result
    end

    # Extract muscle groups from user's goal text
    def extract_muscles_from_goal(goal)
      return nil if goal.blank?

      goal_lower = goal.downcase

      # Keyword to muscle group mapping
      muscle_keywords = {
        "back" => %w[등 광배 광배근 척추 백 back lat pull],
        "chest" => %w[가슴 체스트 흉근 chest pec push],
        "shoulders" => %w[어깨 숄더 삼각근 shoulder delt],
        "legs" => %w[하체 다리 허벅지 대퇴 햄스트링 종아리 leg quad hamstring calf squat],
        "arms" => %w[팔 이두 삼두 이두근 삼두근 bicep tricep arm curl],
        "core" => %w[코어 복근 복부 core abs abdominal plank]
      }

      detected_muscles = []

      muscle_keywords.each do |muscle, keywords|
        if keywords.any? { |kw| goal_lower.include?(kw) }
          detected_muscles << muscle
        end
      end

      # Full body keywords
      fullbody_keywords = %w[전신 풀바디 전체 fullbody full-body]
      if fullbody_keywords.any? { |kw| goal_lower.include?(kw) }
        detected_muscles = %w[legs chest back shoulders core]
      end

      detected_muscles.uniq.presence
    end

    # Build instructions based on whether user specified a goal
    def build_instructions(focus_text, target_muscles, is_user_goal)
      if is_user_goal
        "⚠️ 사용자가 명시적으로 '#{@goal}'을 요청했습니다. " \
        "반드시 #{target_muscles.join(', ')} 근육 중심의 루틴을 구성하세요. " \
        "스케줄보다 사용자 요청을 우선하세요. 반드시 id를 exercise_id로 포함하세요."
      else
        "오늘은 '#{focus_text}' 훈련일입니다. #{target_muscles.join(', ')} 근육을 타겟으로 루틴을 구성하세요. 반드시 id를 exercise_id로 포함하세요."
      end
    end

    def get_recent_workout_history
      # Get last 7 days of workout sessions
      recent_sessions = @user.workout_sessions
                             .where("started_at > ?", 7.days.ago)
                             .includes(:workout_sets)
                             .order(started_at: :desc)
                             .limit(5)

      return [] if recent_sessions.empty?

      recent_sessions.map do |session|
        exercises = session.workout_sets.group_by(&:exercise_name).keys
        {
          date: session.started_at.strftime("%m/%d"),
          exercises: exercises.first(6),
          muscle_groups: session.workout_sets.pluck(:target_muscle).uniq.compact
        }
      end
    rescue StandardError => e
      Rails.logger.warn("Failed to get workout history: #{e.message}")
      []
    end

    # Convert Exercise model to hash with all enriched data
    def exercise_to_hash(ex)
      {
        id: ex.id,
        name: ex.display_name || ex.name,
        difficulty: ex.difficulty,
        equipment: ex.equipment,
        description: ex.description&.truncate(200),
        form_tips: ex.form_tips&.truncate(200),
        video_count: ex.video_references&.size || 0,
        has_video: ex.video_references&.any? || false
      }
    end

    # Tool implementations

    def search_exercises(input)
      muscle = input["muscle"] || input[:muscle]

      # Map Korean muscle names to DB muscle_group values
      muscle_mapping = {
        "가슴" => "chest",
        "등" => "back",
        "어깨" => "shoulders",
        "하체" => "legs",
        "팔" => "arms",
        "코어" => "core",
        "전신" => nil # nil means all
      }
      db_muscle = muscle_mapping[muscle] || muscle

      # 전신 검색 시 더 많은 운동 반환
      default_limit = db_muscle.nil? ? 30 : 10
      limit = input["limit"] || input[:limit] || default_limit

      # Query DB Exercise table directly
      exercises = Exercise.active.for_level(@level)
      exercises = exercises.for_muscle(db_muscle) if db_muscle.present?
      exercises = exercises.order(:difficulty).limit(limit)

      # Filter by movement type if specified
      movement_type = input["movement_type"] || input[:movement_type]
      exercises = filter_by_movement_type_db(exercises, movement_type) if movement_type

      {
        muscle: muscle,
        level: @level,
        exercises: exercises.map do |ex|
          {
            id: ex.id, # Include DB ID
            name: ex.display_name || ex.name,
            target: ex.muscle_group,
            equipment: ex.equipment,
            difficulty: ex.difficulty,
            description: ex.description&.truncate(150),
            form_tips: ex.form_tips&.truncate(150),
            has_video: ex.video_references&.any? || false,
            video_count: ex.video_references&.size || 0
          }
        end,
        total_found: exercises.size,
        note: "반드시 이 목록의 운동만 사용하세요. id를 exercise_id로 포함해주세요. has_video=true인 운동을 우선 선택하세요."
      }
    rescue StandardError => e
      Rails.logger.error("search_exercises failed: #{e.message}")
      { error: "운동 검색 실패", exercises: [] }
    end

    def filter_by_movement_type_db(exercises, movement_type)
      compound_keywords = %w[스쿼트 데드리프트 벤치프레스 로우 프레스 풀업 친업 딥스 런지]
      isolation_keywords = %w[컬 익스텐션 플라이 레이즈 킥백 크런치]
      push_keywords = %w[프레스 푸시 딥스 플라이 레이즈 익스텐션]
      pull_keywords = %w[로우 풀 컬 친업 풀업 데드리프트]

      keywords = case movement_type
                 when "compound" then compound_keywords
                 when "isolation" then isolation_keywords
                 when "push" then push_keywords
                 when "pull" then pull_keywords
                 else return exercises
                 end

      # Build ILIKE conditions for DB query
      conditions = keywords.map { |kw| "name ILIKE '%#{kw}%' OR display_name ILIKE '%#{kw}%'" }
      exercises.where(conditions.join(" OR "))
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

      # Add training program context if available
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

    def parse_routine_response(content)
      json_str = extract_json(content)
      data = JSON.parse(json_str)

      raw_exercises = data["exercises"] || []
      return fallback_routine if raw_exercises.empty?

      exercises = raw_exercises.map.with_index(1) do |ex, idx|
        raw_name = ex["name"] || "운동 #{idx}"
        # Normalize English names to Korean
        exercise_name = ExerciseNameNormalizer.normalize_if_needed(raw_name)
        Rails.logger.info("[ToolBasedRoutineGenerator] Normalized exercise name: '#{raw_name}' → '#{exercise_name}'") if raw_name != exercise_name

        # AI가 제공한 exercise_id 우선 사용
        exercise_id = ex["exercise_id"]
        db_exercise = nil

        if exercise_id.present?
          # ID로 직접 조회 (가장 확실)
          db_exercise = Exercise.find_by(id: exercise_id)
        end

        # ID가 없거나 조회 실패 시 이름으로 fallback (both original and normalized)
        db_exercise ||= find_exercise_by_name(exercise_name)
        db_exercise ||= find_exercise_by_name(raw_name) if raw_name != exercise_name

        # 여전히 없으면 DB에 새로 추가 (with normalized name)
        db_exercise ||= create_exercise_from_ai_response(ex.merge("name" => exercise_name))

        # 시간 기반 운동 판단
        is_time_based = ex["is_time_based"] || time_based_exercise?(exercise_name)
        work_seconds = is_time_based ? (ex["work_seconds"] || ex["reps"] || 30) : nil

        # Fetch video references from Exercise DB (pre-synced data)
        videos = fetch_video_references(exercise_name, exercise_id: db_exercise&.id)

        {
          order: idx,
          exercise_id: db_exercise&.id&.to_s || generate_fallback_id(idx),
          exercise_name: db_exercise&.display_name || exercise_name,
          exercise_name_english: db_exercise&.english_name,
          target_muscle: ex["target_muscle"] || db_exercise&.muscle_group || "전신",
          sets: ex["sets"] || 3,
          reps: is_time_based ? nil : (ex["reps"] || 10),
          work_seconds: work_seconds,
          rpe: ex["rpe"],
          tempo: ex["tempo"],
          rom: ex["rom"],
          rest_seconds: ex["rest_seconds"] || default_rest_for_level,
          weight_guide: ex["weight_guide"],
          # Use AI instructions, fallback to DB form_tips
          instructions: ex["instructions"].presence || db_exercise&.form_tips,
          # Include description from DB
          description: db_exercise&.description,
          source_program: ex["source_program"],
          rest_type: "time_based",
          # Video references from Exercise DB (pre-synced)
          video_references: videos
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
        condition: { score: 3.0, status: "양호", volume_modifier: 1.0, intensity_modifier: 1.0 },
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
        condition: { score: 3.0, status: "양호", volume_modifier: 1.0, intensity_modifier: 1.0 },
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
        build_default_exercise("맨몸 스쿼트", 1, target: "하체", reps: 10),
        build_default_exercise("벤치프레스", 2, target: "가슴", reps: 10),
        build_default_exercise("바벨로우", 3, target: "등", reps: 10),
        build_default_exercise("플랭크", 4, target: "코어", work_seconds: 30, rest: 45)
      ]
    end

    def build_default_exercise(name, order, target:, reps: nil, work_seconds: nil, rest: 90)
      db_exercise = find_exercise_by_name(name)
      is_time_based = work_seconds.present? || time_based_exercise?(name)

      {
        order: order,
        exercise_id: db_exercise&.id&.to_s || generate_fallback_id(order),
        exercise_name: db_exercise&.display_name || name,
        exercise_name_english: db_exercise&.english_name,
        target_muscle: db_exercise&.muscle_group || target,
        sets: 3,
        reps: is_time_based ? nil : reps,
        work_seconds: is_time_based ? (work_seconds || 30) : nil,
        rest_seconds: rest,
        rest_type: "time_based"
      }
    end

    def find_exercise_by_name(name)
      return nil if name.blank?
      return nil unless defined?(Exercise)

      # 정확한 이름 매칭
      exercise = Exercise.find_by(name: name)
      return exercise if exercise

      # display_name으로 매칭
      exercise = Exercise.find_by(display_name: name)
      return exercise if exercise

      # 유사 이름 매칭 (ILIKE)
      Exercise.where("name ILIKE ? OR display_name ILIKE ?", "%#{name}%", "%#{name}%").first
    rescue StandardError => e
      Rails.logger.warn("Exercise lookup failed for '#{name}': #{e.message}")
      nil
    end

    # AI 응답에서 운동 정보를 추출하여 DB에 저장
    def create_exercise_from_ai_response(ex_data)
      exercise_name = ex_data["name"]
      return nil if exercise_name.blank?

      # 영문명 생성 (한글 → kebab-case + timestamp)
      english_name = generate_english_name(exercise_name)

      # 근육 그룹 매핑
      muscle_mapping = {
        "가슴" => "chest", "등" => "back", "어깨" => "shoulders",
        "하체" => "legs", "팔" => "arms", "코어" => "core"
      }
      target = ex_data["target_muscle"] || "chest"
      muscle_group = muscle_mapping[target] || target

      # muscle_group이 유효하지 않으면 기본값 사용
      valid_groups = %w[chest back legs shoulders arms core cardio]
      muscle_group = "chest" unless valid_groups.include?(muscle_group)

      Exercise.create!(
        name: exercise_name,
        english_name: english_name,
        display_name: exercise_name,
        muscle_group: muscle_group,
        difficulty: 3,  # default intermediate
        min_level: 1,   # accessible to all levels
        equipment: [],
        active: true,
        ai_generated: true
      )
    rescue ActiveRecord::RecordInvalid => e
      Rails.logger.warn("Failed to create exercise '#{exercise_name}': #{e.message}")
      nil
    end

    # 한글 이름에서 영문 이름 생성 (unique를 위해 timestamp 포함)
    def generate_english_name(korean_name)
      # 간단한 방식: 특수문자 제거 + timestamp
      base = korean_name.gsub(/[^a-zA-Z0-9가-힣\s]/, "").gsub(/\s+/, "-").downcase
      "#{base}-#{Time.current.to_i}"
    end

    # 시간 기반 운동인지 판단 (운동 이름 기반)
    def time_based_exercise?(name)
      return false if name.blank?

      time_based_keywords = %w[플랭크 홀드 월싯 wall-sit 데드행 버티기 스태틱 static isometric]
      name_lower = name.downcase
      time_based_keywords.any? { |keyword| name_lower.include?(keyword) }
    end

    def generate_fallback_id(idx)
      "TEMP-#{idx}-#{SecureRandom.hex(4)}"
    end

    # Fetch YouTube video references directly from Exercise DB
    # Uses pre-synced video_references from ExerciseKnowledgeSyncService
    def fetch_video_references(exercise_name, exercise_id: nil)
      return [] if exercise_name.blank? && exercise_id.blank?

      # Find exercise by ID or name
      exercise = if exercise_id.present?
        Exercise.find_by(id: exercise_id)
      else
        find_exercise_by_name(exercise_name)
      end

      return [] unless exercise&.video_references&.any?

      # Return top 3 video references with timestamp URLs
      exercise.video_references.first(3).map do |ref|
        url = ref["url"] || "https://www.youtube.com/watch?v=#{ref['video_id']}"
        # Add timestamp to URL if available
        if ref["timestamp_start"].present? && ref["timestamp_start"] > 0
          url += "&t=#{ref['timestamp_start']}"
        end

        {
          title: ref["title"] || ref["summary"]&.truncate(50) || "#{exercise_name} 가이드",
          url: url,
          summary: ref["summary"],
          knowledge_type: ref["knowledge_type"]
        }
      end
    rescue StandardError => e
      Rails.logger.warn("Failed to fetch video references for '#{exercise_name}': #{e.message}")
      []
    end
  end
end
