# frozen_string_literal: true

module Types
  class TrainingLevelEnum < Types::BaseEnum
    description "Training level for workout programs"

    value "BEGINNER", "Beginner level - new to fitness or returning after long break"
    value "INTERMEDIATE", "Intermediate level - consistent training for 6+ months"
    value "ADVANCED", "Advanced level - experienced with 2+ years of training"
  end
end
