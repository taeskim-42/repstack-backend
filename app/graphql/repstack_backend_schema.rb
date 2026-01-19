# frozen_string_literal: true

class RepstackBackendSchema < GraphQL::Schema
  mutation(Types::MutationType)
  query(Types::QueryType)

  # For batch-loading (see https://graphql-ruby.org/dataloader/overview.html)
  use GraphQL::Dataloader

  # GraphQL-Ruby calls this when something goes wrong while running a query
  def self.type_error(err, context)
    # Log the error for monitoring
    Rails.logger.error("[GraphQL Type Error] #{err.message}")
    super
  end

  # Union and Interface Resolution
  # Maps Ruby objects to their corresponding GraphQL types
  def self.resolve_type(abstract_type, obj, ctx)
    case obj
    when User
      Types::UserType
    when UserProfile
      Types::UserProfileType
    when WorkoutSession
      Types::WorkoutSessionType
    when WorkoutSet
      Types::WorkoutSetType
    when WorkoutRoutine
      Types::WorkoutRoutineType
    when RoutineExercise
      Types::RoutineExerciseType
    when Hash
      # Handle hash objects (like routine data from AI)
      resolve_hash_type(obj, abstract_type)
    else
      raise GraphQL::RequiredImplementationMissingError,
            "Cannot resolve type for #{obj.class}. Add it to RepstackBackendSchema.resolve_type"
    end
  end

  # Handle hash-based types
  def self.resolve_hash_type(obj, abstract_type)
    # Return nil for untyped hashes - let GraphQL handle the scalar conversion
    nil
  end

  # Query complexity limits for DoS protection
  max_query_string_tokens(5000)
  max_depth(15)
  max_complexity(300)

  # Stop validating when it encounters this many errors
  validate_max_errors(100)

  # Error handling configuration
  rescue_from(ActiveRecord::RecordNotFound) do |err, obj, args, ctx, field|
    raise GraphQL::ExecutionError.new(
      "Record not found",
      extensions: { code: "NOT_FOUND" }
    )
  end

  rescue_from(ActiveRecord::RecordInvalid) do |err, obj, args, ctx, field|
    raise GraphQL::ExecutionError.new(
      err.record.errors.full_messages.join(", "),
      extensions: { code: "VALIDATION_ERROR" }
    )
  end

  # Relay-style Object Identification

  # Return a string UUID for `object`
  def self.id_from_object(object, type_definition, query_ctx)
    return nil unless object.respond_to?(:to_gid_param)
    object.to_gid_param
  end

  # Given a string UUID, find the object
  def self.object_from_id(global_id, query_ctx)
    return nil if global_id.blank?
    GlobalID.find(global_id)
  rescue ActiveRecord::RecordNotFound
    nil
  end
end
