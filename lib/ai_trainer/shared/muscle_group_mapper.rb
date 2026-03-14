# frozen_string_literal: true

module AiTrainer
  module Shared
    module MuscleGroupMapper
      MUSCLE_KEYWORDS = {
        "등" => %w[등 back 광배 승모 lat],
        "가슴" => %w[가슴 chest 흉근 대흉근 pec],
        "어깨" => %w[어깨 shoulder 삼각근 deltoid],
        "팔" => %w[팔 arm 이두 삼두 bicep tricep],
        "하체" => %w[하체 leg 다리 허벅지 대퇴 quadricep hamstring],
        "코어" => %w[코어 core 복근 abs 복부],
        "전신" => %w[전신 full body 전체]
      }.freeze

      MUSCLE_KR_TO_EN = {
        "가슴" => "chest",
        "등" => "back",
        "어깨" => "shoulders",
        "하체" => "legs",
        "팔" => "arms",
        "복근" => "core",
        "코어" => "core",
        "삼두" => "triceps",
        "이두" => "biceps"
      }.freeze

      VALID_MUSCLE_GROUPS = %w[chest back legs shoulders arms core cardio].freeze

      # Extract target muscle groups from goal text
      def extract_target_muscles(goal)
        goal_lower = goal.downcase
        matched = MUSCLE_KEYWORDS.each_with_object([]) do |(muscle, keywords), arr|
          arr << muscle if keywords.any? { |kw| goal_lower.include?(kw) }
        end
        matched.presence || ["전신"]
      end

      # Translate Korean muscle name to English
      def translate_muscle_to_english(korean_muscle)
        MUSCLE_KR_TO_EN[korean_muscle] || korean_muscle
      end

      # Normalize muscle group to valid English value
      def normalize_muscle_group(target)
        english = MUSCLE_KR_TO_EN[target] || target
        VALID_MUSCLE_GROUPS.include?(english) ? english : "chest"
      end
    end
  end
end
