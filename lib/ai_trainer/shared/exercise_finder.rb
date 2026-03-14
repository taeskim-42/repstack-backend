# frozen_string_literal: true

module AiTrainer
  module Shared
    module ExerciseFinder
      # 3-stage fuzzy exercise lookup: exact name → display_name → ILIKE
      def find_exercise_by_name(name)
        return nil if name.blank?
        return nil unless defined?(Exercise)

        # Exact name match
        exercise = Exercise.find_by(name: name)
        return exercise if exercise

        # Display name match
        exercise = Exercise.find_by(display_name: name)
        return exercise if exercise

        # Fuzzy ILIKE match
        Exercise.where("name ILIKE ? OR display_name ILIKE ?", "%#{name}%", "%#{name}%").first
      rescue StandardError => e
        Rails.logger.warn("Exercise lookup failed for '#{name}': #{e.message}")
        nil
      end

      # Generate temporary ID when DB lookup fails
      def generate_fallback_id(idx)
        "TEMP-#{idx}-#{SecureRandom.hex(4)}"
      end
    end
  end
end
