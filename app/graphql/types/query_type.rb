# frozen_string_literal: true

module Types
  class QueryType < Types::BaseObject
    # Node interface (Relay standard)
    field :node, Types::NodeType, null: true, description: "Fetches an object given its ID." do
      argument :id, ID, required: true, description: "ID of the object."
    end

    def node(id:)
      context.schema.object_from_id(id, context)
    end

    field :nodes, [ Types::NodeType, null: true ], null: true, description: "Fetches a list of objects given a list of IDs." do
      argument :ids, [ ID ], required: true, description: "IDs of the objects."
    end

    def nodes(ids:)
      ids.map { |id| context.schema.object_from_id(id, context) }
    end

    # Health checks
    field :health, String, null: false, description: "Health check endpoint"
    def health
      "ok"
    end

    field :version, String, null: false, description: "API version"
    def version
      "1.0.0"
    end

    # User queries
    field :me, resolver: Queries::Me
    field :my_sessions, resolver: Queries::MySessions
    field :my_routines, resolver: Queries::MyRoutines
    field :today_routine, resolver: Queries::TodayRoutine

    # Workout records
    field :query_workout_records, resolver: Queries::QueryWorkoutRecords

    # Analytics
    field :get_user_level_assessment, resolver: Queries::GetUserLevelAssessment
    field :get_user_condition_logs, resolver: Queries::GetUserConditionLogs
    field :get_workout_analytics, resolver: Queries::GetWorkoutAnalytics
    field :check_level_test_eligibility, resolver: Queries::CheckLevelTestEligibility
    field :check_promotion_readiness, resolver: Queries::CheckPromotionReadiness

    # AI Trainer
    field :get_trainer_greeting, resolver: Queries::GetTrainerGreeting

    # Training Program
    field :my_training_program, resolver: Queries::MyTrainingProgram

    # Subscription & Usage
    field :my_usage_status, resolver: Queries::MyUsageStatus
  end
end
