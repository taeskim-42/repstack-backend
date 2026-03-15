class CreateExerciseVideoClips < ActiveRecord::Migration[8.1]
  def change
    create_table :exercise_video_clips do |t|
      t.references :youtube_video, null: false, foreign_key: true
      t.references :exercise, null: true, foreign_key: true

      t.string :exercise_name, null: false        # english snake_case: "bench_press"
      t.string :muscle_group                       # "chest", "back", "legs" etc
      t.string :clip_type, null: false             # "technique", "form_check", "pro_tip", "common_mistake"

      t.text :title, null: false                   # short title
      t.text :content, null: false                 # detailed knowledge (main language)
      t.text :content_original                     # original text preserved (for English videos)
      t.text :summary                              # one-line summary

      t.float :timestamp_start, null: false        # caption original timestamp (seconds, decimal)
      t.float :timestamp_end, null: false
      t.jsonb :caption_indices, default: []        # original caption line indices (for verification)

      t.string :source_language, null: false, default: "ko"
      t.string :difficulty_level
      t.jsonb :metadata, default: {}
      t.timestamps
    end

    add_index :exercise_video_clips, :exercise_name
    add_index :exercise_video_clips, :source_language
    add_index :exercise_video_clips, [:exercise_name, :source_language]
    add_index :exercise_video_clips, [:exercise_name, :clip_type]
    add_index :exercise_video_clips, [:youtube_video_id, :exercise_name]
  end
end
