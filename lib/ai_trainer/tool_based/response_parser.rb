# frozen_string_literal: true

module AiTrainer
  module ToolBased
    # Parses the LLM's JSON response into a structured routine hash.
    # Depends on: @level, @day_of_week, @goal (from host class)
    # Includes shared utilities instead of duplicating them.
    module ResponseParser
      include AiTrainer::Shared::JsonExtractor
      include AiTrainer::Shared::ExerciseFinder
      include AiTrainer::Shared::TimeBasedExercise
      include AiTrainer::Shared::DayNames
      include AiTrainer::Shared::MuscleGroupMapper

      def parse_routine_response(content)
        json_str = extract_json(content)
        data = JSON.parse(json_str)

        raw_exercises = data["exercises"] || []
        return fallback_routine if raw_exercises.empty?

        exercises = raw_exercises.map.with_index(1) do |ex, idx|
          raw_name = ex["name"] || "운동 #{idx}"
          exercise_name = ExerciseNameNormalizer.normalize_if_needed(raw_name)
          if raw_name != exercise_name
            Rails.logger.info("[ToolBasedRoutineGenerator] Normalized exercise name: '#{raw_name}' → '#{exercise_name}'")
          end

          exercise_id = ex["exercise_id"]
          db_exercise = Exercise.find_by(id: exercise_id) if exercise_id.present?
          db_exercise ||= find_exercise_by_name(exercise_name)
          db_exercise ||= find_exercise_by_name(raw_name) if raw_name != exercise_name
          db_exercise ||= create_exercise_from_ai_response(ex.merge("name" => exercise_name))

          is_time_based = ex["is_time_based"] || time_based_exercise?(exercise_name)
          work_seconds = is_time_based ? (ex["work_seconds"] || ex["reps"] || 30) : nil

          clip_lookup_name = db_exercise&.english_name.presence || exercise_name
          videos = fetch_video_references(clip_lookup_name, exercise_id: db_exercise&.id)

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
            instructions: ex["instructions"].presence || db_exercise&.form_tips,
            description: db_exercise&.description,
            source_program: ex["source_program"],
            rest_type: "time_based",
            video_references: videos
          }
        end

        {
          routine_id: "RT-#{@level}-#{Time.current.to_i}-#{SecureRandom.hex(4)}",
          generated_at: Time.current.iso8601,
          user_level: @level,
          tier: level_to_tier(@level),
          day_of_week: day_name_english(@day_of_week),
          day_korean: day_name_korean(@day_of_week),
          fitness_factor: "strength",
          fitness_factor_korean: data["training_focus"] || "근력 훈련",
          condition: { score: 3.0, status: "양호", volume_modifier: 1.0, intensity_modifier: 1.0 },
          training_type: data["training_focus"],
          exercises: exercises,
          estimated_duration_minutes: data["estimated_duration"] || 45,
          weekly_frequency: data["weekly_frequency"],
          progression: data["progression"],
          variable_adjustments: data["variable_adjustments"],
          notes: [ data["coach_message"] ].compact,
          creative: true,
          goal: @goal
        }
      rescue JSON::ParserError => e
        Rails.logger.error("Failed to parse routine JSON: #{e.message}")
        fallback_routine
      end

      def build_rest_day_response(message)
        {
          routine_id: "RT-REST-#{Time.current.to_i}",
          generated_at: Time.current.iso8601,
          user_level: @level,
          tier: level_to_tier(@level),
          day_of_week: day_name_english(@day_of_week),
          day_korean: day_name_korean(@day_of_week),
          rest_day: true,
          exercises: [],
          estimated_duration_minutes: 0,
          notes: [ message ],
          coach_message: message,
          generation_method: "rest_day"
        }
      end

      # These fallback helpers are unique to this file — they include extra fields
      # (day_korean, condition, generation_method) not present in FallbackRoutineBuilder.
      def fallback_routine
        {
          routine_id: "RT-FALLBACK-#{Time.current.to_i}",
          generated_at: Time.current.iso8601,
          user_level: @level,
          tier: level_to_tier(@level),
          day_of_week: day_name_english(@day_of_week),
          day_korean: day_name_korean(@day_of_week),
          fitness_factor: "general",
          fitness_factor_korean: "기본 훈련",
          condition: { score: 3.0, status: "양호", volume_modifier: 1.0, intensity_modifier: 1.0 },
          training_type: "general",
          exercises: default_exercises,
          estimated_duration_minutes: 45,
          notes: [ "기본 루틴입니다. 컨디션에 맞게 조절하세요." ],
          creative: false,
          goal: @goal,
          generation_method: "fallback"
        }
      end

      def default_exercises
        [
          build_default_exercise("맨몸 스쿼트", 1, target: "하체", reps: 10),
          build_default_exercise("벤치프레스",   2, target: "가슴", reps: 10),
          build_default_exercise("바벨로우",    3, target: "등",   reps: 10),
          build_default_exercise("플랭크",      4, target: "코어", work_seconds: 30, rest: 45)
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

      private

      def create_exercise_from_ai_response(ex_data)
        exercise_name = ex_data["name"]
        return nil if exercise_name.blank?

        english_name = generate_english_name(exercise_name)
        muscle_group = normalize_muscle_group(ex_data["target_muscle"] || "chest")

        Exercise.create!(
          name: exercise_name,
          english_name: english_name,
          display_name: exercise_name,
          muscle_group: muscle_group,
          difficulty: 3,
          min_level: 1,
          equipment: [],
          active: true,
          ai_generated: true
        )
      rescue ActiveRecord::RecordInvalid => e
        Rails.logger.warn("Failed to create exercise '#{exercise_name}': #{e.message}")
        nil
      end

      def generate_english_name(korean_name)
        base = korean_name.gsub(/[^a-zA-Z0-9가-힣\s]/, "").gsub(/\s+/, "-").downcase
        "#{base}-#{Time.current.to_i}"
      end

      def fetch_video_references(exercise_name, exercise_id: nil)
        return [] if exercise_name.blank? && exercise_id.blank?

        # Priority 1: ExerciseVideoClip (accurate timestamps from caption indices)
        if defined?(ExerciseVideoClipService)
          clips = ExerciseVideoClipService.clips_for_exercise(exercise_name, limit: 3)
          if clips.any?
            return clips.map do |clip|
              {
                title: clip.title,
                url: clip.video_url_with_timestamp,
                summary: clip.summary,
                knowledge_type: clip.clip_type
              }
            end
          end
        end

        # Priority 2: Exercise.video_references (legacy)
        exercise = if exercise_id.present?
          Exercise.find_by(id: exercise_id)
        else
          find_exercise_by_name(exercise_name)
        end

        return [] unless exercise&.video_references&.any?

        exercise.video_references.first(3).map do |ref|
          url = ref["url"] || "https://www.youtube.com/watch?v=#{ref['video_id']}"
          url += "&t=#{ref['timestamp_start']}" if ref["timestamp_start"].present? && ref["timestamp_start"] > 0

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
end
