# frozen_string_literal: true

class CreateTrainingPrograms < ActiveRecord::Migration[8.1]
  def change
    create_table :training_programs do |t|
      t.references :user, null: false, foreign_key: true
      t.string :name, null: false
      t.string :status, default: "active"  # active, completed, paused
      t.integer :total_weeks
      t.integer :current_week, default: 1
      t.string :goal
      t.string :periodization_type  # linear, undulating, block
      t.jsonb :weekly_plan, default: {}
      t.jsonb :split_schedule, default: {}
      t.jsonb :generation_context, default: {}  # RAG context and user info used for generation
      t.datetime :started_at
      t.datetime :completed_at
      t.timestamps
    end

    add_index :training_programs, [:user_id, :status]
  end
end
