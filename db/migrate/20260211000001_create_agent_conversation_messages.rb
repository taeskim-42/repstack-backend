# frozen_string_literal: true

class CreateAgentConversationMessages < ActiveRecord::Migration[8.1]
  def change
    create_table :agent_conversation_messages do |t|
      t.references :agent_session, null: false, foreign_key: true
      t.string :role, null: false # "user", "assistant", "tool_result"
      t.jsonb :content, null: false, default: {}
      t.integer :token_count, default: 0
      t.timestamps
    end

    add_index :agent_conversation_messages, [:agent_session_id, :created_at]
  end
end
