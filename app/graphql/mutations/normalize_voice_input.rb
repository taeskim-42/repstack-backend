# frozen_string_literal: true

module Mutations
  class NormalizeVoiceInput < BaseMutation
    description "Normalize voice STT transcript into structured workout data using AI"

    argument :transcript, String, required: true
    argument :exercise_names, [String], required: true

    field :success, Boolean, null: false
    field :exercise, String, null: true
    field :weight, Float, null: true
    field :reps, Int, null: true
    field :sets, Int, null: true
    field :intent, String, null: true
    field :error, String, null: true

    def resolve(transcript:, exercise_names:)
      authenticate!
      AiTrainer::VoiceNormalizerService.normalize(
        transcript: transcript,
        exercise_names: exercise_names
      )
    end
  end
end
