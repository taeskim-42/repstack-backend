# frozen_string_literal: true

module Mutations
  class CheckConditionFromVoice < BaseMutation
    description "Check condition from voice input and get workout adaptations"

    argument :voice_text, String, required: true,
      description: "Voice input text describing user's current condition"

    field :success, Boolean, null: false
    field :condition, Types::ParsedConditionType, null: true
    field :adaptations, [ String ], null: true
    field :intensity_modifier, Float, null: true
    field :duration_modifier, Float, null: true
    field :exercise_modifications, [ String ], null: true
    field :rest_recommendations, [ String ], null: true
    field :interpretation, String, null: true
    field :error, String, null: true

    def resolve(voice_text:)
      authenticate_user!

      # AI directly analyzes voice input and returns condition + adaptations
      result = AiTrainer::ConditionService.analyze_from_voice(user: current_user, text: voice_text)

      unless result[:success]
        return {
          success: false,
          condition: nil,
          adaptations: nil,
          intensity_modifier: nil,
          duration_modifier: nil,
          exercise_modifications: nil,
          rest_recommendations: nil,
          interpretation: nil,
          error: result[:error]
        }
      end

      # Save condition log
      save_condition_log(result[:condition])

      {
        success: true,
        condition: result[:condition],
        adaptations: result[:adaptations],
        intensity_modifier: result[:intensity_modifier],
        duration_modifier: result[:duration_modifier],
        exercise_modifications: result[:exercise_modifications],
        rest_recommendations: result[:rest_recommendations],
        interpretation: result[:interpretation],
        error: nil
      }
    end

    private

    def save_condition_log(condition)
      ConditionLog.create!(
        user: current_user,
        date: Date.current,
        energy_level: condition[:energy_level],
        stress_level: condition[:stress_level],
        sleep_quality: condition[:sleep_quality],
        soreness: condition[:soreness],
        motivation: condition[:motivation],
        available_time: condition[:available_time],
        notes: condition[:notes]
      )
    rescue StandardError => e
      Rails.logger.error("Failed to save condition log: #{e.message}")
    end
  end
end
