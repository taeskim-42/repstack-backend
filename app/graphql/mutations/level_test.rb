# frozen_string_literal: true

module Mutations
  class LevelTest < BaseMutation
    description "Perform AI-powered level assessment test"

    argument :input, Types::LevelTestInputType, required: true,
      description: "Level test input data"

    field :success, Boolean, null: false
    field :level, Types::TrainingLevelEnum, null: true
    field :confidence, Float, null: true
    field :reasoning, String, null: true
    field :fitness_factors, Types::FitnessFactorsType, null: true
    field :recommendations, [String], null: true
    field :error, String, null: true

    def resolve(input:)
      authenticate_user!

      input_hash = input.to_h.deep_transform_keys { |k| k.to_s.underscore.to_sym }
      result = AiTrainerService.level_test(input_hash)

      if result[:success]
        # Save assessment to user profile
        save_assessment(result)

        {
          success: true,
          level: result[:level],
          confidence: result[:confidence],
          reasoning: result[:reasoning],
          fitness_factors: result[:fitness_factors],
          recommendations: result[:recommendations],
          error: nil
        }
      else
        {
          success: false,
          level: nil,
          confidence: nil,
          reasoning: nil,
          fitness_factors: nil,
          recommendations: nil,
          error: result[:error]
        }
      end
    end

    private

    def save_assessment(result)
      profile = current_user.user_profile || current_user.build_user_profile

      # Map level to the profile's current_level format
      level_map = { "BEGINNER" => "beginner", "INTERMEDIATE" => "intermediate", "ADVANCED" => "advanced" }
      profile.current_level = level_map[result[:level]] || "beginner"
      profile.level_assessed_at = Time.current
      profile.fitness_factors = result[:fitness_factors]
      profile.save!
    rescue StandardError => e
      Rails.logger.error("Failed to save assessment: #{e.message}")
    end
  end
end
