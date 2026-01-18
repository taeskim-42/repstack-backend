# frozen_string_literal: true

module Types
  class UserProfileInputType < Types::BaseInputObject
    description "Input type for updating user profile"

    argument :height, Float, required: false, description: "Height in cm"
    argument :weight, Float, required: false, description: "Weight in kg"
    argument :body_fat_percentage, Float, required: false, description: "Body fat percentage"
    argument :fitness_goal, String, required: false, description: "User's fitness goal"
  end
end