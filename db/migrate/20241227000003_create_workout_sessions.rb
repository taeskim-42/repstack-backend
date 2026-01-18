class CreateWorkoutSessions < ActiveRecord::Migration[8.0]
  def change
    create_table :workout_sessions do |t|
      t.references :user, null: false, foreign_key: true
      t.string :name
      t.datetime :start_time, null: false
      t.datetime :end_time
      t.text :notes

      t.timestamps
    end

    add_index :workout_sessions, [:user_id, :start_time]
  end
end