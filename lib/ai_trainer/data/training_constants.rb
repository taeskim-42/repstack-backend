# frozen_string_literal: true

module AiTrainer
  module Data
    module TrainingConstants
      # ============================================================
      # TRAINING VARIABLES (훈련 변인)
      # ============================================================
      TRAINING_VARIABLES = {
        sets: {
          range: 1..10,
          default_by_factor: {
            strength: 3,
            muscular_endurance: "until_target",
            sustainability: "max_possible",
            power: 5,
            cardiovascular: 8
          }
        },
        reps: {
          range: 1..50,
          default_by_factor: {
            strength: 10,
            muscular_endurance: "max_per_set",
            sustainability: 10,
            power: 5,
            cardiovascular: 20
          }
        },
        weight: {
          formula: {
            bench: ->(height, level) { (height - 100) * FitnessConstants::LEVELS[level][:weight_multiplier] },
            squat: ->(height, level) { (height - 100 + 20) * FitnessConstants::LEVELS[level][:weight_multiplier] },
            deadlift: ->(height, level) { (height - 100 + 40) * FitnessConstants::LEVELS[level][:weight_multiplier] }
          },
          description: "체중 기반 또는 RM 기반 계산"
        },
        rack_position: {
          range: 1..9,
          description: "1칸=최저(최대 가동범위/최고 난이도), 9칸=최고(최소 가동범위/보조)",
          default: 5
        },
        bpm: {
          range: 20..120,
          default_by_level: {
            beginner: 30,
            intermediate: 40,
            advanced: "자유 설정"
          },
          description: "메트로놈 템포 (beats per minute)"
        },
        range_of_motion: {
          options: [ :full, :medium, :short ],
          korean: { full: "풀", medium: "중간", short: "깔" },
          default_by_factor: {
            strength: :full,
            muscular_endurance: :full,
            sustainability: :full,
            power: :medium,
            cardiovascular: :short
          }
        },
        rest: {
          time_based: {
            range: 10..180,
            default_by_factor: {
              strength: 60,
              muscular_endurance: 30,
              sustainability: 45,
              power: 90,
              cardiovascular: 10
            }
          },
          heart_rate_based: {
            enabled: true,
            recovery_threshold_formula: ->(max_hr, percentage) { max_hr * percentage },
            default_percentage: 0.6,
            max_wait_seconds: 180
          }
        }
      }.freeze

      # ============================================================
      # TRAINING METHODS (훈련 방법)
      # ============================================================
      TRAINING_METHODS = {
        fixed_sets_reps: {
          id: "TM01",
          korean: "정해진 세트/횟수",
          name: { ko: "정해진 세트/횟수", en: "Fixed Sets & Reps", ja: "固定セット・回数" },
          description: "Perform exactly X sets of Y reps",
          applies_to: [ :strength ]
        },
        total_reps_fill: {
          id: "TM02",
          korean: "채우기",
          name: { ko: "채우기", en: "Total Reps Fill", ja: "トータルレップ" },
          description: "Complete target total reps regardless of sets",
          applies_to: [ :muscular_endurance ]
        },
        max_sets_at_fixed_reps: {
          id: "TM03",
          korean: "지속력 측정",
          name: { ko: "지속력 측정", en: "Max Sets at Fixed Reps", ja: "持続力測定" },
          description: "How many sets of fixed reps can you sustain?",
          applies_to: [ :sustainability ]
        },
        tabata: {
          id: "TM04",
          korean: "타바타",
          name: { ko: "타바타", en: "Tabata", ja: "タバタ" },
          description: "20s work + 10s rest intervals",
          work_duration: 20,
          rest_duration: 10,
          rounds: 8,
          applies_to: [ :cardiovascular ]
        },
        explosive: {
          id: "TM05",
          korean: "폭발적 수행",
          name: { ko: "폭발적 수행", en: "Explosive", ja: "爆発的実行" },
          description: "Maximum speed/power per rep with full recovery",
          applies_to: [ :power ]
        }
      }.freeze

      # ============================================================
      # WEEKLY STRUCTURE (주간 구조)
      # ============================================================
      WEEKLY_STRUCTURE = {
        1 => { day: "Monday", korean: "월요일", day_name: { ko: "월요일", en: "Monday", ja: "月曜日" }, fitness_factor: :strength },
        2 => { day: "Tuesday", korean: "화요일", day_name: { ko: "화요일", en: "Tuesday", ja: "火曜日" }, fitness_factor: :muscular_endurance },
        3 => { day: "Wednesday", korean: "수요일", day_name: { ko: "수요일", en: "Wednesday", ja: "水曜日" }, fitness_factor: :sustainability },
        4 => { day: "Thursday", korean: "목요일", day_name: { ko: "목요일", en: "Thursday", ja: "木曜日" }, fitness_factor: :strength },
        5 => { day: "Friday", korean: "금요일", day_name: { ko: "금요일", en: "Friday", ja: "金曜日" }, fitness_factor: :cardiovascular }
      }.freeze
    end
  end
end
