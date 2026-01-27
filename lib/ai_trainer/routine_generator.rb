# frozen_string_literal: true

require_relative "constants"
require_relative "workout_programs"
require_relative "llm_gateway"

module AiTrainer
  # Generates workout routines using structured WorkoutPrograms
  # Hybrid approach:
  #   - Foundation: Fixed exercises from WorkoutPrograms (Excel program)
  #   - Variables: Adjusted based on condition (sets, reps, weight, etc.)
  #   - Enrichment: YouTube knowledge for tips and instructions
  class RoutineGenerator
    include Constants

    attr_reader :user, :level, :week, :day_of_week, :condition_score, :adjustment, :condition_inputs, :recent_feedbacks

    def initialize(user:, day_of_week: nil, week: nil)
      @user = user
      @level = user.user_profile&.numeric_level || user.user_profile&.level || 1
      @week = week || calculate_current_week
      @day_of_week = day_of_week || Time.current.wday
      @day_of_week = 1 if @day_of_week == 0 # Sunday -> Monday
      @day_of_week = 5 if @day_of_week > 5 # Weekend -> Friday
      @condition_score = 3.0
      @adjustment = Constants::CONDITION_ADJUSTMENTS[:good]
      @condition_inputs = {}
      @recent_feedbacks = []
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

    # Generate a complete routine using structured program + enrichment
    def generate
      workout = WorkoutPrograms.get_workout(level: @level, week: @week, day: @day_of_week)

      unless workout
        return { success: false, error: "해당 주차/요일의 운동 프로그램을 찾을 수 없습니다." }
      end

      exercises = build_exercises(workout)
      enriched_exercises = enrich_with_knowledge(exercises, workout[:training_type])

      build_routine_response(workout, enriched_exercises)
    rescue StandardError => e
      Rails.logger.error("RoutineGenerator error: #{e.message}")
      { success: false, error: "루틴 생성 실패: #{e.message}" }
    end

    private

    # Calculate which week the user is on based on their start date
    def calculate_current_week
      start_date = @user.user_profile&.onboarding_completed_at || @user.created_at
      weeks_elapsed = ((Time.current - start_date) / 1.week).floor
      program = WorkoutPrograms.program_for_level(@level)
      max_weeks = program[:weeks]

      # Cycle through weeks (1-4, then repeat)
      (weeks_elapsed % max_weeks) + 1
    end

    # Build exercises with condition-adjusted variables
    def build_exercises(workout)
      workout[:exercises].map.with_index(1) do |ex, order|
        adjusted = apply_condition_adjustment(ex)

        {
          order: order,
          exercise_id: "EX-#{order}-#{SecureRandom.hex(4)}",
          exercise_name: ex[:name],
          target_muscle: ex[:target],
          sets: adjusted[:sets],
          reps: adjusted[:reps],
          target_total_reps: adjusted[:target_total_reps],
          weight_description: ex[:weight],
          bpm: ex[:bpm],
          range_of_motion: format_rom(ex[:rom]),
          work_seconds: ex[:work_seconds],
          how_to: ex[:how_to],
          rest_seconds: calculate_rest_seconds(workout[:training_type]),
          rest_type: ex[:work_seconds] ? "tabata" : "time_based",
          instructions: ex[:how_to] || default_instruction(workout[:training_type])
        }
      end
    end

    # Apply condition-based adjustments to variables
    def apply_condition_adjustment(exercise)
      sets = exercise[:sets]
      reps = exercise[:reps]
      target_total_reps = nil

      volume_mod = @adjustment[:volume_modifier]
      intensity_mod = @adjustment[:intensity_modifier]

      # For "채우기" style exercises (sets = nil, reps = total target)
      if sets.nil? && reps && reps >= 100
        target_total_reps = (reps * volume_mod).round
        sets = nil
        reps = nil
      elsif sets && reps
        # For fixed sets/reps exercises
        adjusted_sets = (sets * volume_mod).round
        adjusted_reps = (reps * intensity_mod).round

        # Keep reasonable bounds
        sets = [[adjusted_sets, 1].max, sets + 2].min
        reps = [[adjusted_reps, 1].max, reps + 5].min
      end

      { sets: sets, reps: reps, target_total_reps: target_total_reps }
    end

    # Enrich exercises with YouTube knowledge using RAG
    def enrich_with_knowledge(exercises, training_type)
      return exercises unless rag_available?

      # Collect all exercise names and muscle groups for batch search
      exercise_names = exercises.map { |ex| ex[:exercise_name] }.compact
      muscle_groups = exercises.map { |ex| ex[:target_muscle] }.compact.uniq

      # Get contextual knowledge for the entire workout
      contextual_knowledge = fetch_contextual_knowledge(exercise_names, muscle_groups, training_type)

      exercises.map do |ex|
        enrich_single_exercise(ex, contextual_knowledge, training_type)
      end
    rescue StandardError => e
      Rails.logger.warn("Knowledge enrichment failed: #{e.message}")
      exercises
    end

    def rag_available?
      defined?(RagSearchService) && defined?(FitnessKnowledgeChunk)
    end

    def fetch_contextual_knowledge(exercise_names, muscle_groups, training_type)
      return {} unless rag_available?

      # Determine knowledge types based on training type
      knowledge_types = knowledge_types_for_training(training_type)

      # Use RagSearchService for intelligent search
      RagSearchService.contextual_search(
        exercises: exercise_names,
        muscle_groups: muscle_groups,
        knowledge_types: knowledge_types,
        difficulty_level: difficulty_for_level(@level),
        limit: 15
      )
    rescue StandardError => e
      Rails.logger.warn("Contextual knowledge fetch failed: #{e.message}")
      []
    end

    def knowledge_types_for_training(training_type)
      case training_type
      when :strength, :strength_power
        %w[exercise_technique form_check]
      when :muscular_endurance, :sustainability
        %w[exercise_technique routine_design]
      when :cardiovascular
        %w[exercise_technique nutrition_recovery]
      when :form_practice
        %w[form_check exercise_technique]
      when :dropset, :bingo
        %w[exercise_technique routine_design]
      else
        %w[exercise_technique form_check]
      end
    end

    def difficulty_for_level(level)
      case level
      when 1..2 then "beginner"
      when 3..5 then "intermediate"
      when 6..8 then "advanced"
      else "intermediate"
      end
    end

    def enrich_single_exercise(exercise, contextual_knowledge, training_type)
      # Find knowledge relevant to this specific exercise
      relevant = contextual_knowledge.select do |k|
        matches_exercise?(k, exercise[:exercise_name], exercise[:target_muscle])
      end

      # Fallback to direct search if no contextual match
      if relevant.empty?
        relevant = direct_exercise_search(exercise[:exercise_name], exercise[:target_muscle])
      end

      # Build expert tips from knowledge (may be empty)
      tips = build_expert_tips(relevant, training_type)

      exercise[:expert_tips] = tips[:tips] if tips[:tips].present?
      exercise[:form_cues] = tips[:form_cues] if tips[:form_cues].present?

      # Always check and enrich instructions, even if no RAG results
      exercise[:instructions] = enrich_instructions(
        exercise[:instructions],
        tips,
        exercise[:exercise_name],
        training_type
      )

      exercise[:video_references] = tips[:sources] if tips[:sources].present?

      exercise
    end

    def matches_exercise?(knowledge, exercise_name, target_muscle, strict: false)
      return false unless knowledge

      clean_name = exercise_name.gsub(/BPM |타바타 /, "").downcase
      knowledge_name = knowledge[:exercise_name]&.downcase

      # Exact exercise name match (handles comma-separated values)
      if knowledge_name.present?
        knowledge_names = knowledge_name.split(", ").map(&:strip)
        name_match = knowledge_names.include?(clean_name) || knowledge_name == clean_name
        return true if name_match
      end

      # If strict mode or name matched, don't fall back to muscle group
      return false if strict

      # Fallback to muscle group only when no exercise name match
      false
    end

    def muscle_group_matches?(knowledge_muscle, target_muscle)
      mappings = {
        "chest" => %w[가슴 흉근],
        "back" => %w[등 광배근 승모근],
        "legs" => %w[하체 대퇴 허벅지],
        "shoulders" => %w[어깨 삼각근],
        "arms" => %w[팔 이두 삼두],
        "core" => %w[복근 코어 복부]
      }

      mappings.any? do |eng, kor_list|
        (knowledge_muscle.downcase.include?(eng) || kor_list.any? { |k| knowledge_muscle.include?(k) }) &&
          (target_muscle.downcase.include?(eng) || kor_list.any? { |k| target_muscle.include?(k) })
      end
    end

    def direct_exercise_search(exercise_name, target_muscle)
      return [] unless rag_available?

      # Clean exercise name (remove BPM, 타바타 prefixes)
      clean_name = exercise_name.gsub(/BPM |타바타 /, "").strip

      # 1. Try English exercise name (translated from Korean)
      english_name = translate_exercise_to_english(clean_name)
      results = RagSearchService.search_for_exercise(
        english_name,
        knowledge_types: %w[exercise_technique form_check],
        limit: 3
      )

      # 2. If no results, try Korean keyword search in content
      if results.empty?
        results = search_by_korean_keyword(clean_name)
      end

      # 3. If still no results, try original Korean name search
      if results.empty? && english_name != clean_name
        results = RagSearchService.search_for_exercise(
          clean_name,
          knowledge_types: %w[exercise_technique form_check],
          limit: 3
        )
      end

      # 4. If still no results, try muscle group search
      if results.empty? && target_muscle.present?
        results = RagSearchService.search_for_muscle_group(
          translate_muscle_to_english(target_muscle),
          knowledge_types: %w[exercise_technique],
          limit: 2
        )

        # Also try Korean muscle group in keyword search
        if results.empty?
          results = search_by_korean_keyword(target_muscle)
        end
      end

      results
    rescue StandardError => e
      Rails.logger.warn("direct_exercise_search error: #{e.message}")
      []
    end

    def search_by_korean_keyword(keyword)
      return [] if keyword.blank?

      chunks = FitnessKnowledgeChunk
        .keyword_search(keyword)
        .where(knowledge_type: %w[exercise_technique form_check])
        .limit(3)

      RagSearchService.send(:format_results, chunks)
    rescue StandardError
      []
    end

    def translate_exercise_to_english(korean_exercise)
      # Direct mappings for common exercises
      mappings = {
        # Chest
        "푸시업" => "push_up",
        "푸쉬업" => "push_up",
        "벤치프레스" => "bench_press",
        "벤치 프레스" => "bench_press",
        "인클라인 벤치프레스" => "incline_bench_press",
        "덤벨프레스" => "dumbbell_press",
        "덤벨 프레스" => "dumbbell_press",
        "덤벨플라이" => "dumbbell_fly",
        "덤벨 플라이" => "dumbbell_fly",
        "케이블 크로스오버" => "cable_crossover",
        "딥스" => "dips",
        # Back
        "턱걸이" => "pull_up",
        "풀업" => "pull_up",
        "친업" => "pull_up",
        "렛풀다운" => "lat_pulldown",
        "랫풀다운" => "lat_pulldown",
        "렛 풀다운" => "lat_pulldown",
        "시티드로우" => "seated_row",
        "시티드 로우" => "seated_row",
        "케이블로우" => "cable_row",
        "케이블 로우" => "cable_row",
        "바벨로우" => "barbell_row",
        "바벨 로우" => "barbell_row",
        "티바로우" => "t_bar_row",
        "원암 덤벨로우" => "one_arm_dumbbell_row",
        "데드리프트" => "deadlift",
        "랙풀" => "deadlift",
        "랙풀 데드리프트" => "deadlift",
        # Legs
        "스쿼트" => "squat",
        "기둥 스쿼트" => "squat",
        "레그프레스" => "leg_press",
        "레그 프레스" => "leg_press",
        "레그익스텐션" => "leg_extension",
        "레그 익스텐션" => "leg_extension",
        "레그컬" => "leg_curl",
        "레그 컬" => "leg_curl",
        "런지" => "lunge",
        "힙쓰러스트" => "hip_thrust",
        "힙 쓰러스트" => "hip_thrust",
        # Shoulders
        "숄더프레스" => "shoulder_press",
        "숄더 프레스" => "shoulder_press",
        "오버헤드프레스" => "overhead_press",
        "오버헤드 프레스" => "overhead_press",
        "밀리터리프레스" => "overhead_press",
        "사이드 레터럴 레이즈" => "lateral_raise",
        "사이드레터럴레이즈" => "lateral_raise",
        "레터럴레이즈" => "lateral_raise",
        "레터럴 레이즈" => "lateral_raise",
        "측면 레이즈" => "side_lateral_raise",
        "리어델트" => "rear_delt_fly",
        "리어 델트" => "rear_delt_fly",
        "페이스풀" => "face_pull",
        "페이스 풀" => "face_pull",
        # Arms
        "바이셉컬" => "biceps_curl",
        "바이셉스컬" => "biceps_curl",
        "이두컬" => "biceps_curl",
        "덤벨컬" => "biceps_curl",
        "덤벨 컬" => "biceps_curl",
        "해머컬" => "hammer_curl",
        "해머 컬" => "hammer_curl",
        "트라이셉익스텐션" => "tricep_extension",
        "삼두 익스텐션" => "tricep_extension",
        "트라이셉 푸시다운" => "tricep_pushdown",
        "삼두 푸시다운" => "tricep_pushdown",
        # Core
        "복근" => "general",
        "크런치" => "crunch",
        "플랭크" => "plank",
        "레그레이즈" => "leg_raise",
        "레그 레이즈" => "leg_raise"
      }

      # Try exact match first
      return mappings[korean_exercise] if mappings[korean_exercise]

      # Try partial match (for compound names like "9칸 턱걸이")
      mappings.each do |korean, english|
        return english if korean_exercise.include?(korean)
      end

      # Return original if no mapping found
      korean_exercise
    end

    def translate_muscle_to_english(korean_muscle)
      mappings = {
        "가슴" => "chest",
        "등" => "back",
        "어깨" => "shoulders",
        "하체" => "legs",
        "팔" => "arms",
        "복근" => "core",
        "코어" => "core",
        "삼두" => "triceps",
        "이두" => "biceps"
      }

      mappings[korean_muscle] || korean_muscle
    end

    def build_expert_tips(knowledge_chunks, training_type)
      tips = []
      form_cues = []
      sources = []

      knowledge_chunks.each do |chunk|
        case chunk[:type]
        when "exercise_technique"
          tips << extract_tip(chunk[:content], chunk[:summary])
        when "form_check"
          form_cues << extract_form_cue(chunk[:content], chunk[:summary])
        when "routine_design"
          tips << extract_routine_tip(chunk[:content], training_type)
        when "nutrition_recovery"
          tips << chunk[:summary] if chunk[:summary].present?
        end

        # Collect video sources - use summary as title (핵심 내용)
        if chunk[:source].present?
          sources << {
            title: chunk[:summary] || chunk[:source][:video_title],
            url: chunk[:source][:video_url],
            channel: chunk[:source][:channel_name]
          }
        end
      end

      {
        tips: tips.compact.uniq.first(3),
        form_cues: form_cues.compact.uniq.first(2),
        sources: sources.uniq.first(2)
      }
    end

    def extract_tip(content, summary)
      return summary if summary.present? && summary.length < 100

      # Extract first meaningful sentence from content
      sentences = content.to_s.split(/[.!?。]/).map(&:strip).reject(&:empty?)
      tip = sentences.find { |s| s.length > 20 && s.length < 150 }
      tip || summary&.truncate(100)
    end

    def extract_form_cue(content, summary)
      return summary if summary.present?

      # Look for form-related keywords
      content.to_s.split(/[.!?。]/).find do |sentence|
        sentence.match?(/자세|폼|각도|호흡|팔꿈치|무릎|허리|어깨|form|posture/i)
      end&.strip&.truncate(100)
    end

    def extract_routine_tip(content, training_type)
      keywords = case training_type
                 when :strength_power then /증량|무게|점진|드랍/
                 when :muscular_endurance then /반복|채우기|세트/
                 when :cardiovascular then /타바타|인터벌|휴식/
                 else /세트|반복|휴식/
                 end

      content.to_s.split(/[.!?。]/).find { |s| s.match?(keywords) }&.strip&.truncate(100)
    end

    def enrich_instructions(original, tips, exercise_name = nil, training_type = nil)
      # If original is too simple (like "100개 채우기" or "점진적 증량 후 드랍세트"), replace entirely
      if too_simple_instruction?(original)
        return build_rich_instruction(tips, exercise_name, training_type)
      end

      parts = [original]

      if tips[:tips].present?
        parts << "💡 전문가 팁: #{tips[:tips].first}"
      end

      if tips[:form_cues].present?
        parts << "✅ 자세 포인트: #{tips[:form_cues].first}"
      end

      parts.compact.join("\n")
    end

    def too_simple_instruction?(instruction)
      return true if instruction.blank?
      return true if instruction.match?(/^\d+개\s*채우기$/)
      return true if instruction.match?(/운동\s*\d+개\s*채우기/)
      return true if instruction.match?(/점진적.*증량.*드랍세트/)
      return true if instruction.match?(/BPM에\s*맞춰\s*정확한\s*자세/)
      return true if instruction.match?(/목표\s*횟수를\s*채울\s*때까지/)
      return true if instruction.length < 25

      false
    end

    def build_rich_instruction(tips, exercise_name = nil, training_type = nil)
      parts = []

      # Add main tip as instruction
      if tips[:tips].present?
        parts << tips[:tips].first
      end

      # Add form cue
      if tips[:form_cues].present?
        parts << "✅ 자세: #{tips[:form_cues].first}"
      end

      # Add additional tips
      if tips[:tips].present? && tips[:tips].length > 1
        parts << "💡 팁: #{tips[:tips][1]}"
      end

      # If no RAG tips found, generate exercise-specific instruction
      return exercise_specific_instruction(exercise_name, training_type) if parts.empty?

      parts.join("\n")
    end

    def exercise_specific_instruction(exercise_name, training_type)
      # Generate instructions based on exercise name and training type
      base = case exercise_name&.downcase
             when /푸시업|푸쉬업|push/
               "가슴과 삼두에 집중하여 수행하세요. 팔꿈치가 45도를 유지하고, 몸 전체를 일직선으로 유지합니다."
             when /스쿼트|squat/
               "무릎이 발끝을 넘지 않게 주의하세요. 허벅지가 지면과 평행이 될 때까지 앉고, 등은 곧게 유지합니다."
             when /데드리프트|deadlift/
               "허리를 곧게 유지하고 바벨을 몸에 가깝게 붙여서 들어올리세요. 코어에 힘을 주고 수행합니다."
             when /벤치프레스|bench/
               "어깨 견갑골을 모으고 가슴을 활짝 핀 상태에서 수행하세요. 바벨을 내릴 때 팔꿈치 각도 45도를 유지합니다."
             when /렛풀|lat.*pull|풀다운/
               "등 근육으로 당기는 느낌에 집중하세요. 팔꿈치를 몸 쪽으로 당기며, 어깨가 올라가지 않도록 합니다."
             when /로우|row/
               "등 근육 수축에 집중하세요. 팔꿈치를 몸 뒤로 당기며, 어깨를 내리고 견갑골을 모읍니다."
             when /숄더프레스|shoulder|어깨/
               "코어에 힘을 주고 허리가 꺾이지 않게 합니다. 팔꿈치가 어깨 높이에서 시작하여 머리 위로 밀어올립니다."
             when /런지|lunge/
               "무릎이 발끝을 넘지 않게 주의하세요. 앞 허벅지와 뒤 허벅지 모두에 자극을 느끼며 수행합니다."
             when /컬|curl|이두/
               "팔꿈치를 고정하고 이두근으로만 수축하세요. 반동을 사용하지 않고 천천히 수행합니다."
             when /트라이셉|tricep|삼두/
               "팔꿈치를 고정하고 삼두근으로만 밀어내세요. 수축 시 잠시 멈추고 느끼며 수행합니다."
             when /복근|크런치|레그레이즈|플랭크/
               "복부에 힘을 유지하며 수행하세요. 목에 무리가 가지 않도록 시선을 고정합니다."
             when /타바타/
               "20초간 최대 강도로 수행하세요. 짧은 시간 안에 최대한 많은 횟수를 목표로 합니다."
             else
               nil
             end

      # Add training type specific suffix
      suffix = case training_type
               when :strength_power
                 " 점진적으로 무게를 올리며, 실패 지점에서 무게를 낮춰 추가 반복합니다."
               when :muscular_endurance
                 " 목표 횟수를 채울 때까지 세트를 나눠서 완료하세요."
               when :cardiovascular
                 " 20초 운동, 10초 휴식 패턴을 유지합니다."
               when :form_practice
                 " 자세 교정에 집중하고, 느린 템포로 수행하세요."
               else
                 ""
               end

      if base
        "#{base}#{suffix}"
      else
        default_rich_instruction
      end
    end

    def default_rich_instruction
      "정확한 자세로 천천히 수행하세요. 호흡을 유지하고, 목표 근육에 집중합니다."
    end

    # Build the final routine response
    def build_routine_response(workout, exercises)
      program = WorkoutPrograms.program_for_level(@level)
      training_type_info = WorkoutPrograms.training_type_info(workout[:training_type])
      day_info = Constants::WEEKLY_STRUCTURE[@day_of_week]
      fitness_factor = day_info[:fitness_factor]
      fitness_factor_info = Constants::FITNESS_FACTORS[fitness_factor]

      {
        routine_id: generate_routine_id,
        generated_at: Time.current.iso8601,
        user_level: @level,
        tier: Constants.tier_for_level(@level),
        tier_korean: program[:korean],
        week: @week,
        day_of_week: @day_of_week,
        day_korean: day_info[:korean],
        fitness_factor: fitness_factor.to_s,
        fitness_factor_korean: fitness_factor_info[:korean],
        training_type: workout[:training_type].to_s,
        training_type_korean: training_type_info[:korean],
        training_type_description: training_type_info[:description],
        condition: {
          score: @condition_score.round(2),
          status: @adjustment[:korean],
          volume_modifier: @adjustment[:volume_modifier],
          intensity_modifier: @adjustment[:intensity_modifier]
        },
        exercises: exercises,
        purpose: workout[:purpose],
        estimated_duration_minutes: estimate_duration(exercises, workout[:training_type]),
        notes: build_notes(workout, training_type_info)
      }
    end

    def format_rom(rom)
      case rom
      when :full then "full"
      when :medium then "medium"
      when :short then "short"
      else "full"
      end
    end

    def calculate_rest_seconds(training_type)
      case training_type
      when :strength, :strength_power then 90
      when :muscular_endurance then 60
      when :sustainability then 60
      when :cardiovascular then 10 # Tabata rest
      when :form_practice then 120
      else 60
      end
    end

    def default_instruction(training_type)
      case training_type
      when :strength
        "BPM에 맞춰 정확한 자세로 수행하세요."
      when :muscular_endurance
        "목표 횟수를 채울 때까지 최대 횟수로 세트를 수행하세요."
      when :sustainability
        "10개씩 몇 세트까지 지속 가능한지 확인하세요."
      when :cardiovascular
        "20초간 최대한 빠르게 수행 후 10초 휴식하세요."
      when :strength_power
        "점진적으로 무게를 증량한 후, 실패 시점부터 드랍세트로 진행하세요."
      else
        "바른 자세로 천천히 수행하세요."
      end
    end

    def estimate_duration(exercises, training_type)
      base_time = case training_type
      when :cardiovascular then 20 # Tabata is faster
      when :muscular_endurance then 50
      else 45
      end

      # Adjust based on exercise count
      exercise_count = exercises.length
      base_time + (exercise_count - 4) * 5
    end

    def build_notes(workout, training_type_info)
      notes = []

      notes << "#{@week}주차 #{training_type_info[:korean]} 훈련입니다."
      notes << training_type_info[:description]

      if @adjustment[:volume_modifier] < 1.0
        notes << "컨디션을 고려하여 운동량을 조절했습니다."
      elsif @adjustment[:volume_modifier] > 1.0
        notes << "컨디션이 좋으니 조금 더 도전해보세요!"
      end

      notes << workout[:purpose] if workout[:purpose].present?

      notes
    end

    def generate_routine_id
      "RT-#{@level}-W#{@week}-D#{@day_of_week}-#{Time.current.to_i}-#{SecureRandom.hex(4)}"
    end
  end
end
