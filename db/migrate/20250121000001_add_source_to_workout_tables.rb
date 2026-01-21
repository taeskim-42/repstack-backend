# frozen_string_literal: true

class AddSourceToWorkoutTables < ActiveRecord::Migration[8.1]
  def change
    # workout_sessions: track where sessions were created from
    add_column :workout_sessions, :source, :string, default: "app"
    add_index :workout_sessions, :source

    # workout_sets: track where individual sets were recorded from
    add_column :workout_sets, :source, :string, default: "app"
    add_index :workout_sets, :source

    # workout_sets: client_id for offline sync deduplication
    add_column :workout_sets, :client_id, :string
    add_index :workout_sets, :client_id, unique: true
  end
end
