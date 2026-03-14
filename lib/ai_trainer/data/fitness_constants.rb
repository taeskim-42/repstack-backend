# frozen_string_literal: true

module AiTrainer
  module Data
    module FitnessConstants
      # ============================================================
      # FITNESS FACTORS (체력요인)
      # ============================================================
      FITNESS_FACTORS = {
        strength: {
          id: "FF01",
          korean: "근력",
          description: "Maximum force production",
          days: [ 1, 4 ], # Monday, Thursday
          training_method: "fixed_sets_reps",
          typical_bpm: 30,
          typical_rest: 60
        },
        muscular_endurance: {
          id: "FF02",
          korean: "근지구력",
          description: "Sustained muscle performance",
          days: [ 2 ], # Tuesday
          training_method: "total_reps_fill",
          typical_bpm: 30,
          typical_rest: 30
        },
        sustainability: {
          id: "FF03",
          korean: "지속력",
          description: "Continuous performance capacity",
          days: [ 3 ], # Wednesday
          training_method: "max_sets_at_fixed_reps",
          typical_bpm: 30,
          typical_rest: 45
        },
        power: {
          id: "FF04",
          korean: "순발력",
          description: "Explosive force production",
          days: [ 1 ], # Monday (intermediate+)
          training_method: "explosive",
          typical_bpm: nil,
          typical_rest: 90
        },
        cardiovascular: {
          id: "FF05",
          korean: "심폐지구력",
          description: "Heart and lung endurance",
          days: [ 5 ], # Friday
          training_method: "tabata",
          typical_bpm: nil,
          typical_rest: 10
        }
      }.freeze

      # ============================================================
      # LEVELS (레벨 시스템)
      # ============================================================
      LEVELS = {
        1 => { id: "LV01", tier: "beginner", korean_tier: "초급", weight_multiplier: 0.5, description: "Foundation building" },
        2 => { id: "LV02", tier: "beginner", korean_tier: "초급", weight_multiplier: 0.6, description: "Basic movements" },
        3 => { id: "LV03", tier: "intermediate", korean_tier: "중급", weight_multiplier: 0.7, description: "Form refinement" },
        4 => { id: "LV04", tier: "intermediate", korean_tier: "중급", weight_multiplier: 0.8, description: "Volume increase" },
        5 => { id: "LV05", tier: "intermediate", korean_tier: "중급", weight_multiplier: 0.9, description: "Intensity focus" },
        6 => { id: "LV06", tier: "advanced", korean_tier: "고급", weight_multiplier: 1.0, description: "Peak performance" },
        7 => { id: "LV07", tier: "advanced", korean_tier: "고급", weight_multiplier: 1.1, description: "Advanced techniques" },
        8 => { id: "LV08", tier: "advanced", korean_tier: "고급", weight_multiplier: 1.2, description: "Elite training" }
      }.freeze

      # ============================================================
      # GRADES (등급 시스템)
      # ============================================================
      GRADES = {
        normal: { id: "GR01", korean: "정상인", description: "Basic health maintenance", levels: [ 1, 2, 3 ] },
        healthy: { id: "GR02", korean: "건강인", description: "Active lifestyle", levels: [ 4, 5 ] },
        athletic: { id: "GR03", korean: "운동인", description: "Athletic performance", levels: [ 6, 7, 8 ] }
      }.freeze

      # ============================================================
      # FEEDBACK CATEGORIES (피드백 카테고리)
      # ============================================================
      FEEDBACK_CATEGORIES = {
        difficulty: { id: "FB01", korean: "난이도", options: %w[too_easy appropriate too_hard] },
        energy: { id: "FB02", korean: "에너지", options: %w[drained okay energized] },
        enjoyment: { id: "FB03", korean: "만족도", scale: 1..5 },
        pain: { id: "FB04", korean: "통증", body_parts: true, scale: 0..10 },
        time: { id: "FB05", korean: "시간", options: %w[too_short appropriate too_long] }
      }.freeze
    end
  end
end
