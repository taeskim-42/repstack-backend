# frozen_string_literal: true

module Mutations
  class CheckCondition < BaseMutation
    description "Check user's current condition and get workout adaptations"

    argument :input, Types::ConditionInputType, required: true,
      description: "Condition check input data"

    field :success, Boolean, null: false
    field :adaptations, [ String ], null: true
    field :intensity_modifier, Float, null: true
    field :duration_modifier, Float, null: true
    field :exercise_modifications, [ String ], null: true
    field :rest_recommendations, [ String ], null: true
    field :error, String, null: true

    def resolve(input:)
      authenticate_user!

      input_hash = input.to_h.deep_transform_keys { |k| k.to_s.underscore.to_sym }
      result = AiTrainer::ConditionService.analyze_from_input(user: current_user, input: input_hash)

      if result[:success]
        # Save condition log
        save_condition_log(input_hash)

        {
          success: true,
          adaptations: result[:adaptations],
          intensity_modifier: result[:intensity_modifier],
          duration_modifier: result[:duration_modifier],
          exercise_modifications: result[:exercise_modifications],
          rest_recommendations: result[:rest_recommendations],
          error: nil
        }
      else
        {
          success: false,
          adaptations: nil,
          intensity_modifier: nil,
          duration_modifier: nil,
          exercise_modifications: nil,
          rest_recommendations: nil,
          error: result[:error]
        }
      end
    end

    private

    def save_condition_log(input)
      ConditionLog.create!(
        user: current_user,
        date: Date.current,
        energy_level: input[:energy_level],
        stress_level: input[:stress_level],
        sleep_quality: input[:sleep_quality],
        soreness: input[:soreness],
        motivation: input[:motivation],
        available_time: input[:available_time],
        notes: input[:notes]
      )
    rescue StandardError => e
      Rails.logger.error("Failed to save condition log: #{e.message}")
    end
  end
end
