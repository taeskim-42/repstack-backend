# frozen_string_literal: true

require_relative "../shared/muscle_group_mapper"

module AiTrainer
  class RoutineGenerator
    # Enriches exercises with YouTube/RAG knowledge tips and instructions.
    # Depends on host class providing: @level, @adjustment
    module KnowledgeEnricher
      include Shared::MuscleGroupMapper

      # Enrich all exercises with RAG knowledge; falls back gracefully
      def enrich_with_knowledge(exercises, training_type)
        return exercises unless rag_available?

        exercise_names = exercises.map { |ex| ex[:exercise_name] }.compact
        muscle_groups = exercises.map { |ex| ex[:target_muscle] }.compact.uniq

        contextual_knowledge = fetch_contextual_knowledge(exercise_names, muscle_groups, training_type)

        exercises.map { |ex| enrich_single_exercise(ex, contextual_knowledge, training_type) }
      rescue StandardError => e
        Rails.logger.warn("Knowledge enrichment failed: #{e.message}")
        exercises
      end

      private

      def rag_available?
        defined?(RagSearchService) && defined?(FitnessKnowledgeChunk)
      end

      def fetch_contextual_knowledge(exercise_names, muscle_groups, training_type)
        return {} unless rag_available?

        RagSearchService.contextual_search(
          exercises: exercise_names,
          muscle_groups: muscle_groups,
          knowledge_types: knowledge_types_for_training(training_type),
          difficulty_level: difficulty_for_level(@level),
          limit: 15
        )
      rescue StandardError => e
        Rails.logger.warn("Contextual knowledge fetch failed: #{e.message}")
        []
      end

      def knowledge_types_for_training(training_type)
        case training_type
        when :strength, :strength_power then %w[exercise_technique form_check]
        when :muscular_endurance, :sustainability then %w[exercise_technique routine_design]
        when :cardiovascular then %w[exercise_technique nutrition_recovery]
        when :form_practice then %w[form_check exercise_technique]
        when :dropset, :bingo then %w[exercise_technique routine_design]
        else %w[exercise_technique form_check]
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
        # Priority 1: New exercise video clips (direct DB lookup, accurate timestamps)
        clip_name = exercise[:exercise_name_english].presence || exercise[:exercise_name]
        clips = fetch_exercise_clips(clip_name)
        if clips.any?
          exercise[:video_references] = clips.map { |c| ExerciseVideoClipService.format_clip_reference(c) }
          exercise[:expert_tips] = clips.select(&:technique?).map(&:summary).compact.first(2)
          exercise[:form_cues] = clips.select(&:form_check?).map(&:summary).compact.first(2)
        end

        # Priority 2: RAG knowledge (fallback for tips/form_cues if clips didn't provide them)
        if exercise[:expert_tips].blank? || exercise[:form_cues].blank?
          relevant = contextual_knowledge.select do |k|
            matches_exercise?(k, exercise[:exercise_name], exercise[:target_muscle])
          end
          relevant = direct_exercise_search(exercise[:exercise_name], exercise[:target_muscle]) if relevant.empty?

          tips = build_expert_tips(relevant, training_type)
          exercise[:expert_tips] ||= tips[:tips] if tips[:tips].present?
          exercise[:form_cues] ||= tips[:form_cues] if tips[:form_cues].present?
          exercise[:video_references] ||= tips[:sources] if tips[:sources].present?
        end

        exercise[:instructions] = enrich_instructions(
          exercise[:instructions],
          { tips: exercise[:expert_tips], form_cues: exercise[:form_cues] },
          exercise[:exercise_name],
          training_type
        )

        exercise
      end

      def matches_exercise?(knowledge, exercise_name, _target_muscle, strict: false)
        return false unless knowledge

        clean_name = exercise_name.gsub(/BPM |타바타 /, "").downcase
        knowledge_name = knowledge[:exercise_name]&.downcase

        if knowledge_name.present?
          knowledge_names = knowledge_name.split(", ").map(&:strip)
          return true if knowledge_names.include?(clean_name) || knowledge_name == clean_name
        end

        return false if strict

        false
      end

      def direct_exercise_search(exercise_name, target_muscle)
        return [] unless rag_available?

        clean_name = exercise_name.gsub(/BPM |타바타 /, "").strip
        english_name = translate_exercise_to_english(clean_name)

        results = RagSearchService.search_for_exercise(
          english_name, knowledge_types: %w[exercise_technique form_check], limit: 3
        )
        results = search_by_korean_keyword(clean_name) if results.empty?

        if results.empty? && english_name != clean_name
          results = RagSearchService.search_for_exercise(
            clean_name, knowledge_types: %w[exercise_technique form_check], limit: 3
          )
        end

        if results.empty? && target_muscle.present?
          results = RagSearchService.search_for_muscle_group(
            translate_muscle_to_english(target_muscle),
            knowledge_types: %w[exercise_technique], limit: 2
          )
          results = search_by_korean_keyword(target_muscle) if results.empty?
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

      # Delegate to ExerciseNameNormalizer when available; fall back to inline map
      def translate_exercise_to_english(korean_exercise)
        mappings = {
          "푸시업" => "push_up", "푸쉬업" => "push_up",
          "벤치프레스" => "bench_press", "벤치 프레스" => "bench_press",
          "인클라인 벤치프레스" => "incline_bench_press",
          "덤벨프레스" => "dumbbell_press", "덤벨 프레스" => "dumbbell_press",
          "덤벨플라이" => "dumbbell_fly", "덤벨 플라이" => "dumbbell_fly",
          "케이블 크로스오버" => "cable_crossover", "딥스" => "dips",
          "턱걸이" => "pull_up", "풀업" => "pull_up", "친업" => "pull_up",
          "렛풀다운" => "lat_pulldown", "랫풀다운" => "lat_pulldown", "렛 풀다운" => "lat_pulldown",
          "시티드로우" => "seated_row", "시티드 로우" => "seated_row",
          "케이블로우" => "cable_row", "케이블 로우" => "cable_row",
          "바벨로우" => "barbell_row", "바벨 로우" => "barbell_row",
          "티바로우" => "t_bar_row", "원암 덤벨로우" => "one_arm_dumbbell_row",
          "데드리프트" => "deadlift", "랙풀" => "deadlift", "랙풀 데드리프트" => "deadlift",
          "스쿼트" => "squat", "기둥 스쿼트" => "squat",
          "레그프레스" => "leg_press", "레그 프레스" => "leg_press",
          "레그익스텐션" => "leg_extension", "레그 익스텐션" => "leg_extension",
          "레그컬" => "leg_curl", "레그 컬" => "leg_curl",
          "런지" => "lunge", "힙쓰러스트" => "hip_thrust", "힙 쓰러스트" => "hip_thrust",
          "숄더프레스" => "shoulder_press", "숄더 프레스" => "shoulder_press",
          "오버헤드프레스" => "overhead_press", "오버헤드 프레스" => "overhead_press",
          "밀리터리프레스" => "overhead_press",
          "사이드 레터럴 레이즈" => "lateral_raise", "사이드레터럴레이즈" => "lateral_raise",
          "레터럴레이즈" => "lateral_raise", "레터럴 레이즈" => "lateral_raise",
          "측면 레이즈" => "side_lateral_raise",
          "리어델트" => "rear_delt_fly", "리어 델트" => "rear_delt_fly",
          "페이스풀" => "face_pull", "페이스 풀" => "face_pull",
          "바이셉컬" => "biceps_curl", "바이셉스컬" => "biceps_curl",
          "이두컬" => "biceps_curl", "덤벨컬" => "biceps_curl", "덤벨 컬" => "biceps_curl",
          "해머컬" => "hammer_curl", "해머 컬" => "hammer_curl",
          "트라이셉익스텐션" => "tricep_extension", "삼두 익스텐션" => "tricep_extension",
          "트라이셉 푸시다운" => "tricep_pushdown", "삼두 푸시다운" => "tricep_pushdown",
          "복근" => "general", "크런치" => "crunch", "플랭크" => "plank",
          "레그레이즈" => "leg_raise", "레그 레이즈" => "leg_raise"
        }

        return mappings[korean_exercise] if mappings[korean_exercise]

        mappings.each { |korean, english| return english if korean_exercise.include?(korean) }

        korean_exercise
      end

      def build_expert_tips(knowledge_chunks, training_type)
        tips = []
        form_cues = []
        sources = []

        knowledge_chunks.each do |chunk|
          case chunk[:type]
          when "exercise_technique" then tips << extract_tip(chunk[:content], chunk[:summary])
          when "form_check" then form_cues << extract_form_cue(chunk[:content], chunk[:summary])
          when "routine_design" then tips << extract_routine_tip(chunk[:content], training_type)
          when "nutrition_recovery" then tips << chunk[:summary] if chunk[:summary].present?
          end

          if chunk[:source].present?
            sources << {
              title: chunk[:summary] || chunk[:source][:video_title],
              url: chunk[:source][:video_url],
              channel: chunk[:source][:channel_name]
            }
          end
        end

        { tips: tips.compact.uniq.first(3), form_cues: form_cues.compact.uniq.first(2), sources: sources.uniq.first(2) }
      end

      def extract_tip(content, summary)
        return summary if summary.present? && summary.length < 100

        sentences = content.to_s.split(/[.!?。]/).map(&:strip).reject(&:empty?)
        tip = sentences.find { |s| s.length > 20 && s.length < 150 }
        tip || summary&.truncate(100)
      end

      def extract_form_cue(content, summary)
        return summary if summary.present?

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
        return build_rich_instruction(tips, exercise_name, training_type) if too_simple_instruction?(original)

        parts = [ original ]
        parts << "💡 전문가 팁: #{tips[:tips].first}" if tips[:tips].present?
        parts << "✅ 자세 포인트: #{tips[:form_cues].first}" if tips[:form_cues].present?
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
        parts << tips[:tips].first if tips[:tips].present?
        parts << "✅ 자세: #{tips[:form_cues].first}" if tips[:form_cues].present?
        parts << "💡 팁: #{tips[:tips][1]}" if tips[:tips].present? && tips[:tips].length > 1

        return exercise_specific_instruction(exercise_name, training_type) if parts.empty?

        parts.join("\n")
      end

      def exercise_specific_instruction(exercise_name, training_type)
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
        end

        suffix = case training_type
        when :strength_power then " 점진적으로 무게를 올리며, 실패 지점에서 무게를 낮춰 추가 반복합니다."
        when :muscular_endurance then " 목표 횟수를 채울 때까지 세트를 나눠서 완료하세요."
        when :cardiovascular then " 20초 운동, 10초 휴식 패턴을 유지합니다."
        when :form_practice then " 자세 교정에 집중하고, 느린 템포로 수행하세요."
        else ""
        end

        base ? "#{base}#{suffix}" : "정확한 자세로 천천히 수행하세요. 호흡을 유지하고, 목표 근육에 집중합니다."
      end

      def fetch_exercise_clips(exercise_name)
        return [] unless defined?(ExerciseVideoClipService)

        locale = @locale || "ko"
        ExerciseVideoClipService.clips_for_exercise(exercise_name, locale: locale, limit: 5)
      rescue StandardError => e
        Rails.logger.warn("Exercise clip fetch failed for '#{exercise_name}': #{e.message}")
        []
      end
    end
  end
end
