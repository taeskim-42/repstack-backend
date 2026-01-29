# frozen_string_literal: true

module Mutations
  class UpdateUserProfile < BaseMutation
    description "Update individual user profile fields"

    argument :height, Float, required: false
    argument :weight, Float, required: false
    argument :body_fat_percentage, Float, required: false
    argument :current_level, String, required: false
    argument :fitness_goal, String, required: false
    argument :week_number, Integer, required: false
    argument :day_number, Integer, required: false
    argument :numeric_level, Integer, required: false, description: "User's numeric level (1-8)"
    argument :max_lifts, GraphQL::Types::JSON, required: false, description: "Maximum lift records"

    field :user_profile, Types::UserProfileType, null: true
    field :errors, [ String ], null: false

    VALID_LEVELS = %w[beginner intermediate advanced].freeze
    DAY_RANGE = (1..7).freeze
    LEVEL_RANGE = (1..8).freeze

    def resolve(**args)
      with_error_handling(user_profile: nil) do
        user = authenticate!

        profile = user.user_profile || user.build_user_profile

        # Mark onboarding as complete if not already set
        update_attrs = args.compact
        update_attrs[:onboarding_completed_at] ||= Time.current if profile.onboarding_completed_at.nil?

        profile.update!(update_attrs)

        success_response(user_profile: profile)
      end
    end

    private

    def ready?(**args)
      if args[:current_level] && !VALID_LEVELS.include?(args[:current_level])
        raise GraphQL::ExecutionError, "Invalid level. Must be: #{VALID_LEVELS.join(', ')}"
      end

      if args[:day_number] && !DAY_RANGE.include?(args[:day_number])
        raise GraphQL::ExecutionError, "Invalid day number. Must be between #{DAY_RANGE.first} and #{DAY_RANGE.last}"
      end

      if args[:numeric_level] && !LEVEL_RANGE.include?(args[:numeric_level])
        raise GraphQL::ExecutionError, "Invalid numeric level. Must be between #{LEVEL_RANGE.first} and #{LEVEL_RANGE.last}"
      end

      true
    end
  end
end
