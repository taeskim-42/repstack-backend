# frozen_string_literal: true

module AiTrainer
  module Data
    module TrainingParameters
      # ============================================================
      # TRAINING METHODS (훈련 방법) — for dynamic routine generation
      # ============================================================
      DYNAMIC_TRAINING_METHODS = {
        standard: {
          id: "TM01",
          korean: "일반",
          description: "정해진 세트/횟수 수행",
          set_structure: :fixed,
          rest_pattern: :between_sets
        },
        bpm: {
          id: "TM02",
          korean: "BPM",
          description: "메트로놈에 맞춰 일정 속도로 수행",
          set_structure: :fixed,
          rest_pattern: :between_sets,
          tempo_range: 20..60,
          default_tempo: 30
        },
        tabata: {
          id: "TM03",
          korean: "타바타",
          description: "20초 운동 + 10초 휴식 반복",
          set_structure: :interval,
          work_seconds: 20,
          rest_seconds: 10,
          rounds: 8,
          rest_pattern: :fixed_interval
        },
        amrap: {
          id: "TM04",
          korean: "AMRAP",
          description: "시간 내 최대 반복",
          set_structure: :time_based,
          duration_options: [ 5, 10, 15, 20 ], # minutes
          rest_pattern: :self_paced
        },
        emom: {
          id: "TM05",
          korean: "EMOM",
          description: "매 분마다 정해진 횟수 수행",
          set_structure: :time_based,
          duration_options: [ 10, 15, 20 ], # minutes
          rest_pattern: :remaining_time
        },
        dropset: {
          id: "TM06",
          korean: "드랍세트",
          description: "무게를 줄여가며 연속 수행",
          set_structure: :descending_weight,
          drops: 3,
          weight_reduction: 0.2, # 20% per drop
          rest_pattern: :minimal
        },
        superset: {
          id: "TM07",
          korean: "슈퍼세트",
          description: "두 운동을 휴식 없이 연속",
          set_structure: :paired,
          pairing_type: :antagonist, # or :same_muscle
          rest_pattern: :after_pair
        },
        giant_set: {
          id: "TM08",
          korean: "자이언트세트",
          description: "3개 이상 운동을 휴식 없이 연속",
          set_structure: :circuit,
          exercise_count: 3..5,
          rest_pattern: :after_circuit
        },
        fill_target: {
          id: "TM09",
          korean: "채우기",
          description: "목표 총 횟수를 세트 상관없이 채우기",
          set_structure: :flexible,
          target_type: :total_reps,
          rest_pattern: :self_paced
        },
        pyramid: {
          id: "TM10",
          korean: "피라미드",
          description: "무게 증가 → 감소 또는 횟수 감소 → 증가",
          set_structure: :ascending_descending,
          rest_pattern: :between_sets
        }
      }.freeze

      # ============================================================
      # SET SCHEMES (세트 구성)
      # ============================================================
      SET_SCHEMES = {
        fixed: {
          id: "SS01",
          korean: "고정 세트",
          description: "3세트 10회 같은 고정 구성",
          examples: [ "3x10", "4x8", "5x5" ]
        },
        ascending: {
          id: "SS02",
          korean: "오름차순",
          description: "무게 증가, 횟수 감소",
          examples: [ "10-8-6-4", "12-10-8" ]
        },
        descending: {
          id: "SS03",
          korean: "내림차순",
          description: "무게 감소, 횟수 증가",
          examples: [ "6-8-10-12", "5-8-10" ]
        },
        cluster: {
          id: "SS04",
          korean: "클러스터",
          description: "짧은 휴식으로 나눈 미니세트",
          examples: [ "5x2 (10초 휴식)" ]
        },
        rest_pause: {
          id: "SS05",
          korean: "휴식-멈춤",
          description: "실패 후 짧은 휴식 반복",
          examples: [ "8+4+2 (15초 휴식)" ]
        }
      }.freeze

      # ============================================================
      # REP SCHEMES (횟수 구성)
      # ============================================================
      REP_SCHEMES = {
        strength: {
          id: "RS01",
          korean: "근력",
          rep_range: 1..6,
          intensity: "85-100% 1RM",
          rest_seconds: 180..300
        },
        hypertrophy: {
          id: "RS02",
          korean: "근비대",
          rep_range: 6..12,
          intensity: "65-85% 1RM",
          rest_seconds: 60..120
        },
        endurance: {
          id: "RS03",
          korean: "근지구력",
          rep_range: 12..20,
          intensity: "50-65% 1RM",
          rest_seconds: 30..60
        },
        power: {
          id: "RS04",
          korean: "순발력",
          rep_range: 1..5,
          intensity: "30-60% 1RM (explosive)",
          rest_seconds: 120..180
        }
      }.freeze

      # ============================================================
      # ROM OPTIONS (가동범위)
      # ============================================================
      ROM_OPTIONS = {
        full: {
          id: "ROM01",
          korean: "풀",
          description: "전체 가동범위",
          muscle_tension: "최대",
          when_to_use: "기본, 근비대 목적"
        },
        medium: {
          id: "ROM02",
          korean: "중간",
          description: "중간 가동범위 (긴장 유지)",
          muscle_tension: "지속적",
          when_to_use: "타겟 근육 고립, 긴장 유지"
        },
        short: {
          id: "ROM03",
          korean: "깔짝",
          description: "짧은 가동범위 (수축 부분만)",
          muscle_tension: "최대 수축점",
          when_to_use: "고반복, 타바타, 번아웃"
        }
      }.freeze

      # ============================================================
      # REST PATTERNS (휴식 패턴)
      # ============================================================
      REST_PATTERNS = {
        time_based: {
          id: "RP01",
          korean: "시간 기반",
          description: "정해진 시간 휴식",
          options: [ 30, 45, 60, 90, 120, 180 ]
        },
        heart_rate_based: {
          id: "RP02",
          korean: "심박수 기반",
          description: "목표 심박수까지 회복 후 다음 세트",
          recovery_percentage: 0.6..0.7,
          max_wait: 180
        },
        self_paced: {
          id: "RP03",
          korean: "자율",
          description: "준비되면 다음 세트",
          guideline: "호흡이 정상화되면 시작"
        }
      }.freeze
    end
  end
end
