# frozen_string_literal: true

module AiTrainer
  module Data
    module ConditionConstants
      # ============================================================
      # CONDITION INPUTS (컨디션 입력)
      # ============================================================
      CONDITION_INPUTS = {
        sleep: {
          id: "CI01",
          korean: "수면",
          name: { ko: "수면", en: "Sleep", ja: "睡眠" },
          scale: 1..5,
          weight: 0.3,
          description: "Sleep quality last night"
        },
        fatigue: {
          id: "CI02",
          korean: "피로도",
          name: { ko: "피로도", en: "Fatigue", ja: "疲労度" },
          scale: 1..5,
          weight: 0.25,
          description: "Current fatigue level (1=fresh, 5=exhausted)"
        },
        stress: {
          id: "CI03",
          korean: "스트레스",
          name: { ko: "스트레스", en: "Stress", ja: "ストレス" },
          scale: 1..5,
          weight: 0.2,
          description: "Mental stress level"
        },
        soreness: {
          id: "CI04",
          korean: "근육통",
          name: { ko: "근육통", en: "Soreness", ja: "筋肉痛" },
          scale: 1..5,
          weight: 0.15,
          description: "Muscle soreness level"
        },
        motivation: {
          id: "CI05",
          korean: "의욕",
          name: { ko: "의욕", en: "Motivation", ja: "意欲" },
          scale: 1..5,
          weight: 0.1,
          description: "Motivation to workout"
        }
      }.freeze

      # ============================================================
      # CONDITION ADJUSTMENTS (컨디션 조정)
      # ============================================================
      CONDITION_ADJUSTMENTS = {
        excellent: { score_range: 4.0..5.0, volume_modifier: 1.1, intensity_modifier: 1.1, korean: "최상", name: { ko: "최상", en: "Excellent", ja: "最高" } },
        good: { score_range: 3.0...4.0, volume_modifier: 1.0, intensity_modifier: 1.0, korean: "양호", name: { ko: "양호", en: "Good", ja: "良好" } },
        moderate: { score_range: 2.0...3.0, volume_modifier: 0.85, intensity_modifier: 0.9, korean: "보통", name: { ko: "보통", en: "Moderate", ja: "普通" } },
        poor: { score_range: 1.0...2.0, volume_modifier: 0.7, intensity_modifier: 0.75, korean: "나쁨", name: { ko: "나쁨", en: "Poor", ja: "不良" } }
      }.freeze
    end
  end
end
