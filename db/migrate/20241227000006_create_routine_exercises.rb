class CreateRoutineExercises < ActiveRecord::Migration[8.0]
  def change
    create_table :routine_exercises do |t|
      t.references :workout_routine, null: false, foreign_key: true
      t.string :exercise_name, null: false
      t.string :target_muscle
      t.integer :order_index, null: false
      t.integer :sets
      t.integer :reps
      t.decimal :weight, precision: 8, scale: 2
      t.string :weight_description
      t.integer :bpm
      t.integer :rest_duration_seconds
      t.string :range_of_motion
      t.text :how_to
      t.text :purpose

      t.timestamps
    end

    add_index :routine_exercises, [:workout_routine_id, :order_index]
    add_index :routine_exercises, [:exercise_name, :target_muscle]
  end
end