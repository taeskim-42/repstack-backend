# frozen_string_literal: true

class AddProgramReferenceToWorkoutRoutines < ActiveRecord::Migration[8.0]
  def change
    add_reference :workout_routines, :training_program, null: true, foreign_key: true
    add_column :workout_routines, :generation_source, :string, default: "ai"
    add_index :workout_routines, [:training_program_id, :week_number, :day_number],
              name: "idx_routines_program_week_day"
  end
end
