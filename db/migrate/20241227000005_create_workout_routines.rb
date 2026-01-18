class CreateWorkoutRoutines < ActiveRecord::Migration[8.0]
  def change
    create_table :workout_routines do |t|
      t.references :user, null: false, foreign_key: true
      t.string :level, null: false
      t.integer :week_number, null: false
      t.integer :day_number, null: false
      t.string :workout_type
      t.string :day_of_week
      t.integer :estimated_duration
      t.boolean :is_completed, default: false
      t.datetime :completed_at
      t.datetime :generated_at, null: false

      t.timestamps
    end

    add_index :workout_routines, [:user_id, :level, :week_number, :day_number]
    add_index :workout_routines, [:user_id, :is_completed]
  end
end