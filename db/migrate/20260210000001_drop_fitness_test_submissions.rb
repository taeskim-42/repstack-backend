# frozen_string_literal: true

class DropFitnessTestSubmissions < ActiveRecord::Migration[8.0]
  def up
    drop_table :fitness_test_submissions
  end

  def down
    create_table :fitness_test_submissions do |t|
      t.references :user, null: false, foreign_key: true
      t.string :status, null: false, default: "pending"
      t.jsonb :videos, default: [], null: false
      t.jsonb :analyses, default: {}, null: false
      t.jsonb :overall_assessment
      t.string :assessed_level
      t.string :job_id
      t.datetime :completed_at
      t.timestamps
    end

    add_index :fitness_test_submissions, :status
    add_index :fitness_test_submissions, [:user_id, :created_at]
    add_index :fitness_test_submissions, :job_id, unique: true
  end
end
