# frozen_string_literal: true

class AddStatusToWorkoutSessions < ActiveRecord::Migration[7.2]
  def change
    add_column :workout_sessions, :status, :string, default: "pending"
    add_column :workout_sessions, :total_duration, :integer

    add_index :workout_sessions, :status
  end
end
