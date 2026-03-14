# frozen_string_literal: true

module AiTrainer
  module ToolBased
    # Training variable guidelines, condition modifiers, and split programs
    # used by PromptBuilder and ToolExecutor
    module TrainingData
      VARIABLE_GUIDELINES = {
        beginner: {
          sets_per_exercise: 2..3, reps_range: 10..15, rpe_range: 5..7,
          rest_seconds: 90..120, total_sets: 12..16, exercises_count: 4..5,
          tempo: "2-0-2", rom: "full", weekly_frequency: "2-3회/부위",
          progression: "주당 2.5% 또는 1-2회 증가",
          weight_guide: "맨몸 또는 가벼운 무게 (RPE 5-7 유지)",
          notes: "폼 학습 우선, 가벼운 무게로 동작 익히기"
        },
        intermediate: {
          sets_per_exercise: 3..4, reps_range: 8..12, rpe_range: 7..8,
          rest_seconds: 60..90, total_sets: 16..20, exercises_count: 5..6,
          tempo: "2-1-2", rom: "full_with_stretch", weekly_frequency: "2회/부위",
          progression: "주당 2.5-5% 증가, 4주마다 디로드",
          weight_guide: "1RM의 65-75% 또는 RPE 7-8 기준",
          notes: "점진적 과부하, 마인드-머슬 커넥션"
        },
        advanced: {
          sets_per_exercise: 4..5, reps_range: 6..10, rpe_range: 8..9,
          rest_seconds: 60..120, total_sets: 20..25, exercises_count: 5..7,
          tempo: "3-1-2", rom: "varied",
          weekly_frequency: "2회/부위 (고빈도) 또는 1회/부위 (고볼륨)",
          progression: "비선형 주기화, 3주 증가 + 1주 디로드",
          weight_guide: "1RM의 75-85% 또는 RPE 8-9 기준",
          notes: "고강도 테크닉, 볼륨 주기화"
        }
      }.freeze

      CONDITION_MODIFIERS = {
        low_energy:  { volume_modifier: 0.7, intensity_modifier: 0.8, note: "볼륨/강도 감소" },
        moderate:    { volume_modifier: 1.0, intensity_modifier: 1.0, note: "기본 유지" },
        high_energy: { volume_modifier: 1.1, intensity_modifier: 1.0, note: "볼륨 약간 증가 가능" }
      }.freeze

      SPLIT_PROGRAMS = {
        beginner: {
          name: "전신 운동",
          description: "모든 주요 근육을 매 세션에 훈련",
          schedule: {
            1 => { focus: "전신", muscles: %w[legs chest back shoulders core] },
            2 => { focus: "휴식", muscles: [] },
            3 => { focus: "전신", muscles: %w[legs chest back shoulders core] },
            4 => { focus: "휴식", muscles: [] },
            5 => { focus: "전신", muscles: %w[legs chest back shoulders core] }
          }
        },
        intermediate: {
          name: "상하체 분할",
          description: "상체와 하체를 번갈아 훈련",
          schedule: {
            1 => { focus: "상체", muscles: %w[chest back shoulders arms] },
            2 => { focus: "하체", muscles: %w[legs core] },
            3 => { focus: "휴식", muscles: [] },
            4 => { focus: "상체", muscles: %w[chest back shoulders arms] },
            5 => { focus: "하체", muscles: %w[legs core] }
          }
        },
        advanced: {
          name: "PPL 분할",
          description: "밀기-당기기-하체 3분할",
          schedule: {
            1 => { focus: "밀기 (Push)", muscles: %w[chest shoulders arms] },
            2 => { focus: "당기기 (Pull)", muscles: %w[back arms] },
            3 => { focus: "하체 (Legs)", muscles: %w[legs core] },
            4 => { focus: "밀기 (Push)", muscles: %w[chest shoulders arms] },
            5 => { focus: "당기기 (Pull)", muscles: %w[back arms] }
          }
        }
      }.freeze
    end
  end
end
