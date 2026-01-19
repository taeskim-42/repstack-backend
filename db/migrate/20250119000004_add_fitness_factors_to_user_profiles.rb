# frozen_string_literal: true

class AddFitnessFactorsToUserProfiles < ActiveRecord::Migration[8.0]
  def change
    add_column :user_profiles, :fitness_factors, :jsonb, default: {}
    add_column :user_profiles, :level_assessed_at, :datetime
    add_column :user_profiles, :max_lifts, :jsonb, default: {}
  end
end
