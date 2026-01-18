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
    field :user, Types::UserType, null: false

    # Computed fields
    field :bmi, Float, null: true
    field :bmi_category, String, null: false
    field :days_since_start, Integer, null: false

    def program_start_date
      object.program_start_date&.iso8601
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