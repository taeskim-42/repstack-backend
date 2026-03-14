# frozen_string_literal: true

module AiTrainer
  module Data
    module LevelTestConstants
      # ============================================================
      # LEVEL TEST CRITERIA (승급 시험 기준)
      # ============================================================
      LEVEL_TEST_CRITERIA = {
        1 => { bench_ratio: 0.5, squat_ratio: 0.6, deadlift_ratio: 0.7, description: "기초 체력" },
        2 => { bench_ratio: 0.6, squat_ratio: 0.7, deadlift_ratio: 0.8, description: "기본 근력" },
        3 => { bench_ratio: 0.7, squat_ratio: 0.8, deadlift_ratio: 0.9, description: "중급 입문" },
        4 => { bench_ratio: 0.8, squat_ratio: 0.9, deadlift_ratio: 1.0, description: "중급 기본" },
        5 => { bench_ratio: 0.9, squat_ratio: 1.0, deadlift_ratio: 1.1, description: "중급 완성" },
        6 => { bench_ratio: 1.0, squat_ratio: 1.1, deadlift_ratio: 1.2, description: "고급 입문" },
        7 => { bench_ratio: 1.1, squat_ratio: 1.2, deadlift_ratio: 1.3, description: "고급 기본" },
        8 => { bench_ratio: 1.2, squat_ratio: 1.3, deadlift_ratio: 1.4, description: "엘리트" }
      }.freeze
    end
  end
end
