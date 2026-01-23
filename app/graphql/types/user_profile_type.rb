# frozen_string_literal: true

module Types
  class UserProfileType < Types::BaseObject
    field :id, ID, null: false
    field :height, Float, null: true
    field :weight, Float, null: true
    field :body_fat_percentage, Float, null: true
    field :current_level, String, null: true
    field :week_number, Integer, null: false
    field :day_number, Integer, null: false
    field :fitness_goal, String, null: true
    field :program_start_date, String, null: true
    field :numeric_level, Integer, null: true
    field :fitness_factors, GraphQL::Types::JSON, null: true
    field :max_lifts, GraphQL::Types::JSON, null: true
    field :total_workouts_completed, Integer, null: true
    field :level_assessed_at, String, null: true
    field :last_level_test_at, String, null: true
    field :created_at, String, null: false
    field :updated_at, String, null: false
    field :user, Types::UserType, null: false

    # Computed fields
    field :bmi, Float, null: true
    field :bmi_category, String, null: false
    field :days_since_start, Integer, null: false

    def program_start_date
      object.program_start_date&.iso8601
    end

    def level_assessed_at
      object.level_assessed_at&.iso8601
    end

    def last_level_test_at
      object.last_level_test_at&.iso8601
    end

    def created_at
      object.created_at.iso8601
    end

    def updated_at
      object.updated_at.iso8601
    end

    def bmi
      object.bmi
    end

    def bmi_category
      object.bmi_category
    end

    def days_since_start
      object.days_since_start
    end
  end
end
