# frozen_string_literal: true

class AddTrainingDetailsToRoutineExercises < ActiveRecord::Migration[8.0]
  def change
    change_table :routine_exercises, bulk: true do |t|
      t.integer :rpe
      t.string :tempo
      t.text :weight_guide
      t.string :source_program
      t.string :equipment
      t.string :target_muscle_korean
      t.string :exercise_name_english
      t.integer :work_seconds
      t.jsonb :expert_tips, default: []
      t.jsonb :form_cues, default: []
    end
  end
end
