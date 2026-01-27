# frozen_string_literal: true

class CreateChatMessages < ActiveRecord::Migration[8.0]
  def change
    create_table :chat_messages do |t|
      t.references :user, null: false, foreign_key: true
      t.string :role, null: false  # 'user' or 'assistant'
      t.text :content, null: false
      t.string :session_id  # Group messages by session
      t.jsonb :metadata, default: {}  # For storing context like current_routine, etc.

      t.timestamps
    end

    add_index :chat_messages, [:user_id, :session_id, :created_at]
    add_index :chat_messages, [:user_id, :created_at]
  end
end
