# frozen_string_literal: true

module Types
  class ChatDataType < Types::BaseObject
    description "Data returned by chat API based on intent"

    field :routine, Types::AiRoutineType, null: true, description: "Generated routine (GENERATE_ROUTINE)"
    field :records, [ Types::WorkoutRecordItemType ], null: true, description: "Workout records (QUERY_RECORDS, RECORD_EXERCISE)"
    field :summary, Types::RecordSummaryType, null: true, description: "Record summary (QUERY_RECORDS)"
    field :feedback, Types::FeedbackAnalysisType, null: true, description: "Feedback analysis (SUBMIT_FEEDBACK)"
    field :condition, Types::ConditionAnalysisType, null: true, description: "Condition analysis (CHECK_CONDITION)"
    field :is_complete, Boolean, null: true, description: "Assessment completion status (LEVEL_ASSESSMENT)"
    field :assessment, Types::LevelAssessmentType, null: true, description: "Level assessment result (LEVEL_ASSESSMENT)"

    # Promotion eligibility (PROMOTION_ELIGIBLE)
    field :current_level, Integer, null: true, description: "Current user level"
    field :target_level, Integer, null: true, description: "Target level for promotion"
    field :target_tier, String, null: true, description: "Target tier (beginner/intermediate/advanced)"
    field :estimated_1rms, GraphQL::Types::JSON, null: true, description: "Estimated 1RM for each lift"
    field :required_1rms, GraphQL::Types::JSON, null: true, description: "Required 1RM for promotion"
    field :exercise_results, GraphQL::Types::JSON, null: true, description: "Per-exercise promotion status"
  end
end
