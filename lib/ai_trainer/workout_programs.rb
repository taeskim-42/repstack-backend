# frozen_string_literal: true

require_relative "data/programs/beginner"
require_relative "data/programs/intermediate"
require_relative "data/programs/advanced"
require_relative "data/programs/shimhyundo"
require_relative "data/programs/kimsunghwan"
require_relative "workout_programs/exercise_pool"

module AiTrainer
  # Structured workout programs based on Excel 운동프로그램
  # Programs include:
  # - 운동프로그램[초급/중급/고급].xlsx
  # - 심현도_무분할 루틴.xlsx (8 levels)
  # - 김성환님 운동루틴.xlsx (phase-based)
  module WorkoutPrograms
    # Training types
    TRAINING_TYPES = {
      strength: { korean: "근력", description: "BPM 맞춰서 정해진 세트/횟수 수행" },
      strength_power: { korean: "근력 + 순발력", description: "점진적 증량 후 드랍" },
      muscular_endurance: { korean: "근지구력", description: "목표 횟수 채우기" },
      sustainability: { korean: "지속력", description: "몇 세트까지 지속 가능한지 확인" },
      cardiovascular: { korean: "심폐지구력", description: "타바타 20초 운동 + 10초 휴식" },
      form_practice: { korean: "자세연습", description: "트레이너 지도 하에 자세 연습" },
      dropset: { korean: "드랍세트", description: "점진적 무게 감량하며 반복" },
      bingo: { korean: "빙고", description: "여러 무게로 이어서 수행" }
    }.freeze

    # Range of motion options
    ROM = {
      full: { korean: "풀", description: "전체 가동범위" },
      medium: { korean: "중(몸-중)", description: "중간 가동범위" },
      short: { korean: "깔", description: "짧은 가동범위 (깔짝)" }
    }.freeze

    # Program data constants (delegated to data files)
    BEGINNER = AiTrainer::Data::Programs::Beginner::BEGINNER
    INTERMEDIATE = AiTrainer::Data::Programs::Intermediate::INTERMEDIATE
    ADVANCED = AiTrainer::Data::Programs::Advanced::ADVANCED
    SHIMHYUNDO = AiTrainer::Data::Programs::Shimhyundo::SHIMHYUNDO
    KIMSUNGHWAN = AiTrainer::Data::Programs::Kimsunghwan::KIMSUNGHWAN

    # Exercise pool methods (delegated to ExercisePool module)
    extend AiTrainer::WorkoutPrograms::ExercisePool

    class << self
      def program_for_level(level)
        numeric = level.to_s.to_i
        case level.to_s.downcase
        when "beginner", "초급"
          BEGINNER
        when "intermediate", "중급"
          INTERMEDIATE
        when "advanced", "고급"
          ADVANCED
        when "shimhyundo", "심현도"
          SHIMHYUNDO
        when "kimsunghwan", "김성환"
          KIMSUNGHWAN
        else
          # Numeric level mapping
          if numeric >= 1 && numeric <= 2
            BEGINNER
          elsif numeric >= 3 && numeric <= 5
            INTERMEDIATE
          elsif numeric >= 6 && numeric <= 8
            ADVANCED
          else
            BEGINNER
          end
        end
      end

      def get_workout(level:, week:, day:)
        program = program_for_level(level)
        return nil unless program

        # Handle different program structures
        if program[:program]
          week_num = [ [ week, 1 ].max, program[:weeks] ].min
          day_num = [ [ day, 1 ].max, 5 ].min
          program.dig(:program, week_num, day_num)
        elsif program[:phases]
          # For phase-based programs like KIMSUNGHWAN
          nil # Requires different handling
        else
          nil
        end
      end

      def get_shimhyundo_workout(level:, day:)
        level_num = [ [ level.to_i, 1 ].max, 8 ].min
        day_num = [ [ day.to_i, 1 ].max, 6 ].min
        SHIMHYUNDO.dig(:program, level_num, day_num)
      end

      def get_kimsunghwan_phase(phase_name)
        KIMSUNGHWAN.dig(:phases, phase_name.to_sym)
      end

      def training_type_info(type)
        TRAINING_TYPES[type] || TRAINING_TYPES[:strength]
      end

      def all_programs
        {
          beginner: BEGINNER,
          intermediate: INTERMEDIATE,
          advanced: ADVANCED,
          shimhyundo: SHIMHYUNDO,
          kimsunghwan: KIMSUNGHWAN
        }
      end
    end
  end
end
