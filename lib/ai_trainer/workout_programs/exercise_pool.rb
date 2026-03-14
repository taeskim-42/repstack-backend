# frozen_string_literal: true

module AiTrainer
  module WorkoutPrograms
    # Exercise pool: extracts exercises from all programs
    # Mixed into WorkoutPrograms via extend
    module ExercisePool
      # Muscle group mappings for normalization
      MUSCLE_ALIASES = {
        "등" => %w[등 back 광배 승모 lat 후면],
        "가슴" => %w[가슴 chest 흉근 대흉근 pec],
        "어깨" => %w[어깨 shoulder 삼각근 deltoid],
        "하체" => %w[하체 leg 다리 허벅지 대퇴 quad hamstring 둔근 종아리 calf],
        "이두" => %w[이두 bicep 팔 앞],
        "삼두" => %w[삼두 tricep],
        "코어" => %w[코어 core 복근 abs 복부],
        "전신" => %w[전신 full compound]
      }.freeze

      # Get exercises from all programs for a specific muscle and level
      # @param level [Integer] User level (1-8)
      # @param target_muscle [String] Target muscle group
      # @param limit_per_program [Integer] Max exercises per program source
      # @return [Array<Hash>] Array of exercise hashes with source info
      def get_exercise_pool(level:, target_muscle:, limit_per_program: 5)
        exercises = []
        normalized_muscle = normalize_muscle(target_muscle)

        # 1. 초/중/고급 프로그램에서 추출
        tier_exercises = extract_from_tier_programs(level, normalized_muscle, limit_per_program)
        exercises.concat(tier_exercises)

        # 2. 심현도 프로그램에서 추출
        shimhyundo_exercises = extract_from_shimhyundo(level, normalized_muscle, limit_per_program)
        exercises.concat(shimhyundo_exercises)

        # 3. 김성환 프로그램에서 추출
        kimsunghwan_exercises = extract_from_kimsunghwan(level, normalized_muscle, limit_per_program)
        exercises.concat(kimsunghwan_exercises)

        # 중복 제거 (이름 기준) 및 정렬
        deduplicate_exercises(exercises)
      end

      # Get all training patterns/types from programs
      def get_training_patterns(level:)
        patterns = []

        # 초/중/고급의 training_type들
        tier = level <= 2 ? BEGINNER : (level <= 5 ? INTERMEDIATE : ADVANCED)
        if tier[:program]
          tier[:program].each do |_week, days|
            days.each do |_day, workout|
              next unless workout.is_a?(Hash) && workout[:training_type]
              patterns << {
                type: workout[:training_type],
                info: TRAINING_TYPES[workout[:training_type]],
                source: tier[:korean]
              }
            end
          end
        end

        patterns.uniq { |p| p[:type] }
      end

      private

      def normalize_muscle(muscle)
        muscle_lower = muscle.to_s.downcase
        MUSCLE_ALIASES.each do |canonical, aliases|
          return canonical if aliases.any? { |a| muscle_lower.include?(a) }
        end
        muscle # Return as-is if no match
      end

      def muscle_matches?(exercise_target, normalized_muscle)
        return true if normalized_muscle == "전신"
        target_lower = exercise_target.to_s.downcase
        aliases = MUSCLE_ALIASES[normalized_muscle] || [ normalized_muscle ]
        aliases.any? { |a| target_lower.include?(a) }
      end

      def extract_from_tier_programs(level, target_muscle, limit)
        exercises = []
        tier = level <= 2 ? BEGINNER : (level <= 5 ? INTERMEDIATE : ADVANCED)

        return exercises unless tier[:program]

        tier[:program].each do |week_num, days|
          days.each do |day_num, workout|
            next unless workout.is_a?(Hash) && workout[:exercises]

            workout[:exercises].each do |ex|
              next unless muscle_matches?(ex[:target], target_muscle)

              exercises << build_exercise_entry(ex, {
                source: "#{tier[:korean]} #{week_num}주차 #{day_num}일",
                program: tier[:korean],
                training_type: workout[:training_type]
              })
            end
          end
        end

        exercises.uniq { |e| e[:name] }.first(limit)
      end

      def extract_from_shimhyundo(level, target_muscle, limit)
        exercises = []
        shimhyundo_level = [ [ level, 1 ].max, 8 ].min

        return exercises unless SHIMHYUNDO[:program]

        # 해당 레벨과 인접 레벨에서 추출
        [ shimhyundo_level, shimhyundo_level - 1, shimhyundo_level + 1 ].each do |lv|
          next if lv < 1 || lv > 8
          level_data = SHIMHYUNDO[:program][lv]
          next unless level_data

          level_data.each do |day_num, workout|
            next unless workout.is_a?(Hash) && workout[:exercises]

            workout[:exercises].each do |ex|
              next unless muscle_matches?(ex[:target], target_muscle)

              exercises << build_exercise_entry(ex, {
                source: "심현도 레벨#{lv} #{day_num}일",
                program: "심현도 무분할",
                training_type: workout[:training_type]
              })
            end
          end
        end

        exercises.uniq { |e| e[:name] }.first(limit)
      end

      def extract_from_kimsunghwan(level, target_muscle, limit)
        exercises = []

        return exercises unless KIMSUNGHWAN[:phases]

        # 레벨에 따른 phase 선택
        phases_to_check = if level <= 2
                            [ :beginner_prep, :beginner ]
        elsif level <= 5
                            [ :intermediate ]
        else
                            [ :intermediate ] # 고급도 intermediate 내의 고급 분할 사용
        end

        phases_to_check.each do |phase_key|
          phase = KIMSUNGHWAN[:phases][phase_key]
          next unless phase

          # 직접 exercises가 있는 경우
          if phase[:exercises]
            phase[:exercises].each do |ex|
              next unless muscle_matches?(ex[:target], target_muscle)
              exercises << build_exercise_entry(ex, {
                source: "김성환 #{phase[:name]}",
                program: "김성환 루틴",
                training_type: :strength
              })
            end
          end

          # 중첩된 phases (intermediate의 four_split, five_split 등)
          if phase[:phases]
            phase[:phases].each do |sub_phase_key, sub_phase|
              next unless sub_phase[:schedule]

              sub_phase[:schedule].each do |day_key, day_data|
                next unless day_data.is_a?(Hash) && day_data[:exercises]

                day_data[:exercises].each do |ex|
                  # day_data[:target]으로 근육 매칭
                  day_target = day_data[:target].to_s
                  next unless muscle_matches?(day_target, target_muscle) ||
                              muscle_matches?(ex[:target] || ex[:name], target_muscle)

                  exercises << build_exercise_entry(ex, {
                    source: "김성환 #{sub_phase[:name]} #{day_key}",
                    program: "김성환 루틴",
                    training_type: :strength
                  })
                end
              end
            end
          end
        end

        exercises.uniq { |e| e[:name] }.first(limit)
      end

      def build_exercise_entry(ex, metadata)
        {
          name: ex[:name],
          target: ex[:target],
          sets: ex[:sets],
          reps: ex[:reps],
          weight: ex[:weight],
          bpm: ex[:bpm],
          rom: ex[:rom],
          how_to: ex[:how_to],
          source: metadata[:source],
          program: metadata[:program],
          training_type: metadata[:training_type]
        }.compact
      end

      def deduplicate_exercises(exercises)
        # 이름 기준 그룹핑, 여러 소스에서 온 경우 병합
        grouped = exercises.group_by { |e| e[:name].to_s.downcase.gsub(/\s+/, "") }

        grouped.map do |_key, group|
          base = group.first.dup
          if group.size > 1
            # 여러 프로그램에서 등장 - sources 병합
            base[:sources] = group.map { |e| e[:source] }.uniq
            base[:programs] = group.map { |e| e[:program] }.uniq
          end
          base
        end
      end

      def calculate_weight_for_shimhyundo(exercise:, level:, user_height:)
        standards = SHIMHYUNDO[:weight_standards]
        return nil unless standards[exercise.to_sym]

        base_formula = standards[exercise.to_sym][:base]
        multiplier = standards[exercise.to_sym][:level_multiplier][level - 1] || 1

        base_weight = case base_formula
        when /키 - 100/
                        user_height - 100
        when /\(키 - 100\) \+ 20/
                        (user_height - 100) + 20
        when /\(키 - 100\) \+ 40/
                        (user_height - 100) + 40
        else
                        0
        end

        (base_weight * multiplier).round
      end
    end
  end
end
