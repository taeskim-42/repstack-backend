# frozen_string_literal: true

class AddNumericLevelToUserProfiles < ActiveRecord::Migration[8.0]
  def change
    add_column :user_profiles, :numeric_level, :integer, default: 1
    add_column :user_profiles, :last_level_test_at, :datetime
    add_column :user_profiles, :total_workouts_completed, :integer, default: 0

    add_index :user_profiles, :numeric_level
  end
end
