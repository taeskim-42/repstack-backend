# frozen_string_literal: true

class CreateWorkoutFeedbacks < ActiveRecord::Migration[8.0]
  def change
    create_table :workout_feedbacks do |t|
      t.references :user, null: false, foreign_key: true
      t.bigint :workout_record_id
      t.bigint :routine_id
      t.string :feedback_type, null: false
      t.integer :rating, null: false
      t.text :feedback, null: false
      t.jsonb :suggestions, default: []
      t.boolean :would_recommend, null: false, default: true

      t.timestamps
    end

    add_index :workout_feedbacks, :workout_record_id
    add_index :workout_feedbacks, :routine_id
  end
end
