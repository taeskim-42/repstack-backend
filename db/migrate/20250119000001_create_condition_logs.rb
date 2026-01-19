# frozen_string_literal: true

class CreateConditionLogs < ActiveRecord::Migration[8.0]
  def change
    create_table :condition_logs do |t|
      t.references :user, null: false, foreign_key: true
      t.date :date, null: false
      t.integer :energy_level, null: false
      t.integer :stress_level, null: false
      t.integer :sleep_quality, null: false
      t.jsonb :soreness, default: {}
      t.integer :motivation, null: false
      t.integer :available_time, null: false
      t.text :notes

      t.timestamps
    end

    add_index :condition_logs, [ :user_id, :date ]
  end
end
