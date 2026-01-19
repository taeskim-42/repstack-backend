# frozen_string_literal: true

class AddAiTrainerFieldsToWorkoutSets < ActiveRecord::Migration[8.0]
  def change
    add_column :workout_sets, :target_muscle, :string
    add_column :workout_sets, :set_number, :integer
    add_column :workout_sets, :rpe, :integer

    add_index :workout_sets, :target_muscle
  end
end
