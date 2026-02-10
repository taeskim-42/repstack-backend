# frozen_string_literal: true

class CreateAgentSessions < ActiveRecord::Migration[8.1]
  def change
    create_table :agent_sessions do |t|
      t.references :user, null: false, foreign_key: true
      t.string :claude_session_id, null: false
      t.string :status, default: "active", null: false
      t.integer :message_count, default: 0
      t.integer :total_tokens, default: 0
      t.decimal :total_cost_usd, precision: 8, scale: 4, default: 0
      t.datetime :last_active_at
      t.timestamps
    end

    add_index :agent_sessions, :claude_session_id, unique: true
    add_index :agent_sessions, [:user_id, :status]
    add_index :agent_sessions, :last_active_at
  end
end
