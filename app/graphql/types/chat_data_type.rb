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
  end
end
