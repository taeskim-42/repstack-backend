# frozen_string_literal: true

module AiTrainer
  module Data
    module SplitTypes
      # ============================================================
      # SPLIT TYPES (분할 유형)
      # ============================================================
      SPLIT_TYPES = {
        full_body: {
          id: "SP01",
          korean: "무분할",
          description: "전신 운동을 매일 수행",
          days_per_week: 3..5,
          muscle_groups_per_day: %w[chest back legs shoulders arms core],
          suitable_for_levels: 1..3,
          pros: "회복 시간 짧음, 초보자에게 적합",
          cons: "고급자에게는 볼륨 부족"
        },
        upper_lower: {
          id: "SP02",
          korean: "2분할 (상/하)",
          description: "상체와 하체를 번갈아 수행",
          days_per_week: 4,
          schedule: {
            upper: %w[chest back shoulders arms],
            lower: %w[legs core]
          },
          suitable_for_levels: 2..5,
          pros: "균형 잡힌 발달, 적절한 회복",
          cons: "주 4일 필요"
        },
        push_pull_legs: {
          id: "SP03",
          korean: "3분할 (밀기/당기기/하체)",
          description: "밀기/당기기/하체로 분할",
          days_per_week: 3..6,
          schedule: {
            push: %w[chest shoulders triceps],
            pull: %w[back biceps rear_delts],
            legs: %w[quadriceps hamstrings glutes core]
          },
          suitable_for_levels: 3..8,
          pros: "효율적인 근육 분리, 충분한 회복",
          cons: "주 3일 미만은 불가"
        },
        four_day: {
          id: "SP04",
          korean: "4분할",
          description: "가슴/등/어깨+팔/하체로 분할",
          days_per_week: 4,
          schedule: {
            day1: %w[chest triceps],
            day2: %w[back biceps],
            day3: %w[shoulders arms],
            day4: %w[legs core]
          },
          suitable_for_levels: 4..8,
          pros: "각 근육군 집중 가능",
          cons: "주 4일 필수"
        },
        five_day: {
          id: "SP05",
          korean: "5분할",
          description: "가슴/등/어깨/팔/하체 각각 분리",
          days_per_week: 5,
          schedule: {
            chest: %w[chest],
            back: %w[back],
            shoulders: %w[shoulders],
            arms: %w[biceps triceps forearms],
            legs: %w[quadriceps hamstrings glutes core]
          },
          suitable_for_levels: 5..8,
          pros: "최대 볼륨, 각 부위 집중",
          cons: "주 5일 필수, 회복 시간 길어짐"
        },
        fitness_factor_based: {
          id: "SP06",
          korean: "체력요인 기반",
          description: "요일별로 다른 체력요인 훈련",
          days_per_week: 5,
          schedule: {
            monday: { factor: :strength, korean: "근력" },
            tuesday: { factor: :muscular_endurance, korean: "근지구력" },
            wednesday: { factor: :sustainability, korean: "지속력" },
            thursday: { factor: :strength, korean: "근력" },
            friday: { factor: :cardiovascular, korean: "심폐지구력" }
          },
          suitable_for_levels: 1..8,
          pros: "균형 잡힌 체력 발달",
          cons: "근비대보다 체력 향상 목적"
        }
      }.freeze
    end
  end
end
