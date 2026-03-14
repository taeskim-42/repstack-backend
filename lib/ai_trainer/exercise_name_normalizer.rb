# frozen_string_literal: true

require_relative "data/exercise_name_dictionary"

module AiTrainer
  # Normalizes exercise names from English to Korean
  # Shared between ToolBasedRoutineGenerator and rake tasks
  module ExerciseNameNormalizer
    include AiTrainer::Data::ExerciseNameDictionary

    module_function

    # Normalize a single exercise name
    # Returns Korean name if found, otherwise returns original
    def normalize(name)
      return name if name.blank?

      normalized_key = name.to_s.downcase.strip

      # Direct match first
      return ENGLISH_TO_KOREAN[normalized_key] if ENGLISH_TO_KOREAN.key?(normalized_key)

      # Partial match
      ENGLISH_TO_KOREAN.each do |eng, kor|
        return kor if normalized_key.include?(eng) || eng.include?(normalized_key)
      end

      # Already Korean or no match found
      name
    end

    # Check if name is already in Korean
    def korean?(name)
      return false if name.blank?
      name.to_s.match?(/[가-힣]/)
    end

    # Normalize only if not already Korean
    def normalize_if_needed(name)
      return name if korean?(name)
      normalize(name)
    end
  end
end
