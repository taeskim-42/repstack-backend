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

    # General chat fields
    field :session_id, String, null: true, description: "Chat session ID for continuous conversation"
    field :knowledge_used, Boolean, null: true, description: "Whether RAG knowledge was used"

    # Promotion eligibility (PROMOTION_ELIGIBLE)
    field :current_level, Integer, null: true, description: "Current user level"
    field :target_level, Integer, null: true, description: "Target level for promotion"
    field :target_tier, String, null: true, description: "Target tier (beginner/intermediate/advanced)"
    field :estimated_1rms, GraphQL::Types::JSON, null: true, description: "Estimated 1RM for each lift"
    field :required_1rms, GraphQL::Types::JSON, null: true, description: "Required 1RM for promotion"
    field :exercise_results, GraphQL::Types::JSON, null: true, description: "Per-exercise promotion status"

    # Routine modification fields (REPLACE_EXERCISE, ADD_EXERCISE, REGENERATE_ROUTINE)
    field :new_exercise, Types::RoutineExerciseType, null: true, description: "Newly replaced exercise (REPLACE_EXERCISE)"
    field :added_exercise, Types::RoutineExerciseType, null: true, description: "Added exercise (ADD_EXERCISE)"
    field :remaining_replacements, Integer, null: true, description: "Remaining exercise replacements today"
    field :remaining_regenerations, Integer, null: true, description: "Remaining routine regenerations today"
    field :deleted_exercise, String, null: true, description: "Deleted exercise name (DELETE_EXERCISE)"
    field :deleted_routine_id, ID, null: true, description: "Deleted routine ID (DELETE_ROUTINE)"

    # Welcome/Long-term plan fields
    field :is_first_chat, Boolean, null: true, description: "Whether this is the first chat after onboarding"
    field :user_profile, GraphQL::Types::JSON, null: true, description: "User profile summary"
    field :long_term_plan, Types::LongTermPlanType, null: true, description: "Long-term workout plan"
    field :suggestions, [ String ], null: true, description: "Suggested follow-up messages"
  end
end
