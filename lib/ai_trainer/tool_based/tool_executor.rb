# frozen_string_literal: true

module AiTrainer
  module ToolBased
    # Dispatches and executes all LLM tool calls.
    # Depends on: @user, @level, @day_of_week, @goal, @condition (from host class)
    # Depends on: level_to_tier, tier_korean, extract_condition_text (PromptBuilder)
    module ToolExecutor
      include TrainingData
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
        when "get_routine_data"   then get_routine_data
        when "search_exercises"   then search_exercises(tool_use[:input])
        when "get_training_variables" then get_training_variables(tool_use[:input])
        when "get_program_pattern"    then get_program_pattern(tool_use[:input])
        when "get_rag_knowledge"      then get_rag_knowledge(tool_use[:input])
        else { error: "Unknown tool: #{tool_use[:name]}" }
        end
      end

      private

      # Single tool that returns all data needed for routine generation
      def get_routine_data
        tier = level_to_tier(@level)
        variables = VARIABLE_GUIDELINES[tier].dup
        split = SPLIT_PROGRAMS[tier]
        today_schedule = split[:schedule][@day_of_week] || split[:schedule][1]

        program = @user.active_training_program
        program_context = nil

        if program.present?
          program_context = build_program_context(program)
          program_today = program.today_focus(@day_of_week)

          if program_today.present? && program_today["muscles"].present?
            today_schedule = { focus: program_today["focus"], muscles: program_today["muscles"] }
          elsif program_today.nil? || rest_day?(program_today)
            if @goal.blank?
              Rails.logger.info("[ToolBasedRoutineGenerator] Rest day detected (day=#{@day_of_week}, goal=nil)")
              return { rest_day: true, message: "오늘은 프로그램에 따른 휴식일입니다. 충분한 회복을 취하세요! 💤" }
            end
            Rails.logger.info("[ToolBasedRoutineGenerator] Rest day but user has goal: #{@goal}")
            fallback_day = program.training_days.first
            if fallback_day
              today_schedule = { focus: fallback_day[:focus], muscles: fallback_day[:muscles] }
              Rails.logger.info("[ToolBasedRoutineGenerator] Using fallback training day: #{today_schedule}")
            end
          end

          volume_mod = program.current_volume_modifier
          if volume_mod != 1.0
            original_min = variables[:total_sets].min
            original_max = variables[:total_sets].max
            variables[:total_sets] = ((original_min * volume_mod).round)..((original_max * volume_mod).round)
          end
        end

        goal_muscles = extract_muscles_from_goal(@goal) if @goal.present?
        Rails.logger.info("[ToolBasedRoutineGenerator] Goal: #{@goal.inspect}, extracted muscles: #{goal_muscles.inspect}")

        target_muscles = if goal_muscles.present?
          Rails.logger.info("[ToolBasedRoutineGenerator] Using GOAL-based muscles: #{goal_muscles}")
          goal_muscles
        else
          Rails.logger.info("[ToolBasedRoutineGenerator] Using SCHEDULE-based muscles: #{today_schedule[:muscles]}")
          today_schedule[:muscles]
        end

        exercises_by_muscle = build_exercises_by_muscle(target_muscles)
        recent_history = get_recent_workout_history

        focus_text = goal_muscles.present? ? "사용자 요청: #{@goal}" : today_schedule[:focus]

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

      def build_exercises_by_muscle(target_muscles)
        exercises_by_muscle = {}

        if target_muscles.empty?
          exercises = Exercise.active.for_level(@level).for_muscle("core").order(:difficulty).limit(5)
          exercises_by_muscle["core"] = exercises.map { |ex| exercise_to_hash(ex) }
        else
          target_muscles.each do |muscle|
            exercises = Exercise.active.for_level(@level).for_muscle(muscle).order(:difficulty).limit(8)
            exercises_by_muscle[muscle] = exercises.map { |ex| exercise_to_hash(ex) }
          end
        end

        exercises_by_muscle
      end

      def search_exercises(input)
        muscle = input["muscle"] || input[:muscle]

        muscle_mapping = {
          "가슴" => "chest", "등" => "back", "어깨" => "shoulders",
          "하체" => "legs", "팔" => "arms", "코어" => "core",
          "전신" => nil
        }
        db_muscle = muscle_mapping[muscle] || muscle

        default_limit = db_muscle.nil? ? 30 : 10
        limit = input["limit"] || input[:limit] || default_limit

        exercises = Exercise.active.for_level(@level)
        exercises = exercises.for_muscle(db_muscle) if db_muscle.present?
        exercises = exercises.order(:difficulty).limit(limit)

        movement_type = input["movement_type"] || input[:movement_type]
        exercises = filter_by_movement_type_db(exercises, movement_type) if movement_type

        {
          muscle: muscle,
          level: @level,
          exercises: exercises.map do |ex|
            {
              id: ex.id,
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
            rom: variables[:rom],
            weekly_frequency: variables[:weekly_frequency],
            progression: variables[:progression],
            weight_guide: variables[:weight_guide],
            training_notes: variables[:notes]
          }
        }

        include_condition = input["include_condition_adjustment"] || input[:include_condition_adjustment]
        if include_condition && @condition
          result[:condition_info] = {
            user_stated: extract_condition_text,
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

        if defined?(EmbeddingService) && EmbeddingService.pgvector_available? && EmbeddingService.configured?
          query_embedding = EmbeddingService.generate_query_embedding(query)

          if query_embedding.present?
            return FitnessKnowledgeChunk
              .where(knowledge_type: knowledge_type)
              .where.not(embedding: nil)
              .for_user_level(@level)
              .nearest_neighbors(:embedding, query_embedding, distance: "cosine")
              .limit(limit)
              .map { |c| { content: c.content, summary: c.summary, exercise_name: c.exercise_name, video_id: c.youtube_video_id } }
          end
        end

        FitnessKnowledgeChunk
          .where(knowledge_type: knowledge_type)
          .where("content ILIKE ? OR summary ILIKE ?", "%#{query}%", "%#{query}%")
          .for_user_level(@level)
          .limit(limit)
          .map { |c| { content: c.content, summary: c.summary, exercise_name: c.exercise_name, video_id: c.youtube_video_id } }
      rescue StandardError => e
        Rails.logger.warn("RAG search failed: #{e.message}")
        []
      end

      def filter_by_movement_type_db(exercises, movement_type)
        compound_keywords  = %w[스쿼트 데드리프트 벤치프레스 로우 프레스 풀업 친업 딥스 런지]
        isolation_keywords = %w[컬 익스텐션 플라이 레이즈 킥백 크런치]
        push_keywords      = %w[프레스 푸시 딥스 플라이 레이즈 익스텐션]
        pull_keywords      = %w[로우 풀 컬 친업 풀업 데드리프트]

        keywords = case movement_type
        when "compound"  then compound_keywords
        when "isolation" then isolation_keywords
        when "push"      then push_keywords
        when "pull"      then pull_keywords
        else return exercises
        end

        conditions = keywords.map { |kw| "name ILIKE '%#{kw}%' OR display_name ILIKE '%#{kw}%'" }
        exercises.where(conditions.join(" OR "))
      end

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

      def extract_muscles_from_goal(goal)
        return nil if goal.blank?

        goal_lower = goal.downcase
        muscle_keywords = {
          "back"      => %w[등 광배 광배근 척추 백 back lat pull],
          "chest"     => %w[가슴 체스트 흉근 chest pec push],
          "shoulders" => %w[어깨 숄더 삼각근 shoulder delt],
          "legs"      => %w[하체 다리 허벅지 대퇴 햄스트링 종아리 leg quad hamstring calf squat],
          "arms"      => %w[팔 이두 삼두 이두근 삼두근 bicep tricep arm curl],
          "core"      => %w[코어 복근 복부 core abs abdominal plank]
        }

        detected = muscle_keywords.each_with_object([]) do |(muscle, keywords), arr|
          arr << muscle if keywords.any? { |kw| goal_lower.include?(kw) }
        end

        fullbody_keywords = %w[전신 풀바디 전체 fullbody full-body]
        detected = %w[legs chest back shoulders core] if fullbody_keywords.any? { |kw| goal_lower.include?(kw) }

        detected.uniq.presence
      end

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
        recent_sessions = @user.workout_sessions
                               .where("start_time > ?", 7.days.ago)
                               .includes(:workout_sets)
                               .order(start_time: :desc)
                               .limit(5)

        return [] if recent_sessions.empty?

        recent_sessions.map do |session|
          exercises = session.workout_sets.group_by(&:exercise_name).keys
          {
            date: session.start_time.strftime("%m/%d"),
            exercises: exercises.first(6),
            muscle_groups: session.workout_sets.pluck(:target_muscle).uniq.compact
          }
        end
      rescue StandardError => e
        Rails.logger.warn("Failed to get workout history: #{e.message}")
        []
      end

      def rest_day?(schedule_entry)
        return true if schedule_entry.nil?

        focus = schedule_entry["focus"]&.downcase || ""
        muscles = schedule_entry["muscles"]
        %w[휴식 rest off].any? { |kw| focus.include?(kw) } || muscles.blank? || muscles.empty?
      end
    end
  end
end
