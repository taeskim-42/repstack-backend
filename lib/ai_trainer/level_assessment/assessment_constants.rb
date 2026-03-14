# frozen_string_literal: true

module AiTrainer
  module LevelAssessment
    # Shared constants for assessment submodules
    module AssessmentConstants
      PROMPT_VERSION = "v2.0-flexible"

      STATES = {
        initial: "initial",
        asking_experience: "asking_experience",
        asking_frequency: "asking_frequency",
        asking_goals: "asking_goals",
        asking_limitations: "asking_limitations",
        completed: "completed"
      }.freeze
    end
  end
end
