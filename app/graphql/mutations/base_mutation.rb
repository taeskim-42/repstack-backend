# frozen_string_literal: true

module Mutations
  class BaseMutation < GraphQL::Schema::RelayClassicMutation
    argument_class Types::BaseArgument
    field_class Types::BaseField
    input_object_class Types::BaseInputObject
    object_class Types::BaseObject

    private

    # Returns the authenticated user or raises GraphQL::ExecutionError
    # Use this method when authentication is required
    def authenticate!
      user = context[:current_user]
      raise GraphQL::ExecutionError, "Authentication required" unless user
      user
    end

    # Returns the current user or nil (for optional authentication)
    def current_user
      context[:current_user]
    end

    # Check if user is authenticated without raising error
    def authenticated?
      context[:current_user].present?
    end

    # Build a standard error response hash
    # @param errors [Array<String>, String] - error message(s)
    # @param fields [Hash] - additional fields to include (all set to nil)
    def error_response(errors, **fields)
      errors = Array(errors)
      fields.transform_values { nil }.merge(errors: errors)
    end

    # Build a standard success response hash
    # @param fields [Hash] - fields to include in response
    def success_response(**fields)
      fields.merge(errors: [])
    end

    # Wrap mutation logic with standard error handling
    # @yield block containing mutation logic
    # @param error_fields [Hash] - fields to return on error (all set to nil)
    def with_error_handling(**error_fields)
      yield
    rescue ActiveRecord::RecordInvalid => e
      error_response(e.record.errors.full_messages, **error_fields)
    rescue ActiveRecord::RecordNotFound => e
      error_response(e.message, **error_fields)
    rescue GraphQL::ExecutionError
      raise # Re-raise GraphQL errors as-is
    rescue StandardError => e
      Rails.logger.error("Mutation error: #{e.class} - #{e.message}")
      Rails.logger.error(e.backtrace&.first(5)&.join("\n")) if Rails.env.development?
      error_response(e.message, **error_fields)
    end
  end
end
