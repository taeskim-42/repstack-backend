# frozen_string_literal: true

class CreateWorkoutRecords < ActiveRecord::Migration[8.0]
  def change
    create_table :workout_records do |t|
      t.references :user, null: false, foreign_key: true
      t.references :workout_session, null: true, foreign_key: true
      t.bigint :routine_id
      t.datetime :date, null: false
      t.integer :total_duration, null: false
      t.integer :calories_burned
      t.integer :average_heart_rate
      t.integer :perceived_exertion, null: false
      t.string :completion_status, null: false, default: "COMPLETED"

      t.timestamps
    end

    add_index :workout_records, [ :user_id, :date ]
  end
end
