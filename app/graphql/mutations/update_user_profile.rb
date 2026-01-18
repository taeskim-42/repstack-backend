module Mutations
  class UpdateUserProfile < BaseMutation
    argument :height, Float, required: false
    argument :weight, Float, required: false
    argument :body_fat_percentage, Float, required: false
    argument :current_level, String, required: false
    argument :fitness_goal, String, required: false
    argument :week_number, Integer, required: false
    argument :day_number, Integer, required: false

    field :user_profile, Types::UserProfileType, null: true
    field :errors, [String], null: false

    def resolve(**args)
      user = context[:current_user]
      
      unless user
        return {
          user_profile: nil,
          errors: ['Authentication required']
        }
      end

      profile = user.user_profile || user.build_user_profile

      if profile.update(args.compact)
        {
          user_profile: profile,
          errors: []
        }
      else
        {
          user_profile: nil,
          errors: profile.errors.full_messages
        }
      end
    rescue StandardError => e
      {
        user_profile: nil,
        errors: [e.message]
      }
    end

    private

    def ready?(**args)
      if args[:current_level] && !%w[beginner intermediate advanced].include?(args[:current_level])
        raise GraphQL::ExecutionError, 'Invalid level. Must be beginner, intermediate, or advanced'
      end

      if args[:day_number] && !(1..7).include?(args[:day_number])
        raise GraphQL::ExecutionError, 'Invalid day number. Must be between 1 and 7'
      end

      true
    end
  end
end