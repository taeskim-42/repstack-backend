# frozen_string_literal: true

# Service to validate GraphQL schema matches database schema
# Detects mismatches between DB columns and GraphQL fields
class SchemaValidator
  # Mapping of ActiveRecord models to their GraphQL types
  MODEL_TYPE_MAPPING = {
    User => Types::UserType,
    UserProfile => Types::UserProfileType,
    WorkoutSession => Types::WorkoutSessionType,
    WorkoutSet => Types::WorkoutSetType,
    WorkoutRoutine => Types::WorkoutRoutineType,
    RoutineExercise => Types::RoutineExerciseType,
    WorkoutRecord => Types::WorkoutRecordSummaryType,
    WorkoutFeedback => Types::FeedbackSummaryType,
    ConditionLog => Types::UserConditionLogType
  }.freeze

  # Columns that should never be exposed in GraphQL (security)
  SECURITY_EXCLUDED_COLUMNS = %w[
    password_digest
    encrypted_password
    reset_password_token
    apple_user_id
  ].freeze

  # Columns with default values (not truly nullable in practice)
  COLUMNS_WITH_DEFAULTS = %w[
    week_number
    day_number
    weight_unit
    is_completed
    numeric_level
    total_workouts_completed
    status
    completion_status
    would_recommend
  ].freeze

  # Columns that are optional to expose (can be excluded without warning)
  OPTIONAL_COLUMNS = %w[
    created_at
    updated_at
  ].freeze

  # Foreign keys that don't need association exposure (context-aware types)
  CONTEXT_AWARE_FK_EXCLUSIONS = {
    "WorkoutRecord" => %w[user_id],
    "WorkoutFeedback" => %w[user_id]
  }.freeze

  # Computed fields that exist in GraphQL but not in DB
  COMPUTED_FIELDS = {
    "Types::UserType" => %w[
      user_profile workout_sessions workout_routines
      current_workout_session has_active_workout total_workout_sessions
    ],
    "Types::UserProfileType" => %w[user bmi bmi_category days_since_start],
    "Types::WorkoutSessionType" => %w[
      workout_sets user active completed duration_in_seconds
      duration_formatted total_sets exercises_performed total_volume
    ],
    "Types::WorkoutSetType" => %w[
      workout_session volume is_timed_exercise is_weighted_exercise
      duration_formatted weight_in_kg weight_in_lbs
    ],
    "Types::WorkoutRoutineType" => %w[
      routine_exercises user total_exercises total_sets
      estimated_duration_formatted workout_summary day_name
    ],
    "Types::RoutineExerciseType" => %w[
      workout_routine estimated_exercise_duration rest_duration_formatted
      is_cardio is_strength exercise_summary target_muscle_group
    ],
    "Types::WorkoutRecordSummaryType" => %w[],
    "Types::FeedbackSummaryType" => %w[],
    "Types::UserConditionLogType" => %w[]
  }.freeze

  Result = Struct.new(:valid?, :errors, :warnings, keyword_init: true)
  FieldMismatch = Struct.new(:model, :type, :field, :issue, keyword_init: true)

  def validate
    errors = []
    warnings = []

    MODEL_TYPE_MAPPING.each do |model, graphql_type|
      result = validate_model(model, graphql_type)
      errors.concat(result[:errors])
      warnings.concat(result[:warnings])
    end

    Result.new(valid?: errors.empty?, errors: errors, warnings: warnings)
  end

  def validate_model(model, graphql_type)
    errors = []
    warnings = []

    db_columns = model.columns.map(&:name)
    # GraphQL fields are in camelCase, convert to snake_case for comparison
    graphql_fields_camel = graphql_type.fields.keys
    graphql_fields_snake = graphql_fields_camel.map { |f| f.underscore }
    computed = COMPUTED_FIELDS[graphql_type.to_s] || []
    context_fk_exclusions = CONTEXT_AWARE_FK_EXCLUSIONS[model.name] || []

    # Check for DB columns not in GraphQL
    db_columns.each do |col|
      next if SECURITY_EXCLUDED_COLUMNS.include?(col)
      next if computed.include?(col)
      next if graphql_fields_snake.include?(col)
      next if context_fk_exclusions.include?(col)

      # Foreign keys are often exposed as associations (user_id -> user field)
      if col.end_with?("_id")
        association_name = col.sub(/_id$/, "")
        next if graphql_fields_snake.include?(association_name)
      end

      if OPTIONAL_COLUMNS.include?(col)
        warnings << FieldMismatch.new(
          model: model.name,
          type: graphql_type.to_s,
          field: col,
          issue: "DB column not exposed in GraphQL (optional)"
        )
      else
        errors << FieldMismatch.new(
          model: model.name,
          type: graphql_type.to_s,
          field: col,
          issue: "DB column not exposed in GraphQL"
        )
      end
    end

    # Check nullable mismatches
    db_columns.each do |col|
      camel_col = col.camelize(:lower)
      next unless graphql_fields_camel.include?(camel_col)
      # Skip columns with defaults (they have values even if DB allows null)
      next if COLUMNS_WITH_DEFAULTS.include?(col)

      db_column = model.columns_hash[col]
      graphql_field = graphql_type.fields[camel_col]

      db_nullable = db_column.null
      graphql_nullable = graphql_field.type.non_null? == false

      if db_nullable && !graphql_nullable
        errors << FieldMismatch.new(
          model: model.name,
          type: graphql_type.to_s,
          field: col,
          issue: "Nullable mismatch: DB allows null, GraphQL requires non-null"
        )
      end
    end

    { errors: errors, warnings: warnings }
  end

  def print_report
    result = validate

    puts "\n" + "=" * 60
    puts "GraphQL-DB Schema Validation Report"
    puts "=" * 60

    if result.valid? && result.warnings.empty?
      puts "\n✅ All schemas are in sync!"
    else
      if result.errors.any?
        puts "\n❌ ERRORS (#{result.errors.count}):"
        result.errors.each do |error|
          puts "  - [#{error.model}] #{error.field}: #{error.issue}"
        end
      end

      if result.warnings.any?
        puts "\n⚠️  WARNINGS (#{result.warnings.count}):"
        result.warnings.each do |warning|
          puts "  - [#{warning.model}] #{warning.field}: #{warning.issue}"
        end
      end
    end

    puts "\n" + "=" * 60
    result
  end
end
