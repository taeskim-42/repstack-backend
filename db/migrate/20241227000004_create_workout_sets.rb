class CreateWorkoutSets < ActiveRecord::Migration[8.0]
  def change
    create_table :workout_sets do |t|
      t.references :workout_session, null: false, foreign_key: true
      t.string :exercise_name, null: false
      t.decimal :weight, precision: 8, scale: 2
      t.string :weight_unit, default: 'kg'
      t.integer :reps
      t.integer :duration_seconds
      t.text :notes

      t.timestamps
    end

    add_index :workout_sets, [ :workout_session_id, :exercise_name ]
  end
end
