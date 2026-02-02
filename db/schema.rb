# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.1].define(version: 2026_02_01_000000) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"

  create_table "chat_messages", force: :cascade do |t|
    t.text "content", null: false
    t.datetime "created_at", null: false
    t.jsonb "metadata", default: {}
    t.string "role", null: false
    t.string "session_id"
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["user_id", "created_at"], name: "index_chat_messages_on_user_id_and_created_at"
    t.index ["user_id", "session_id", "created_at"], name: "index_chat_messages_on_user_id_and_session_id_and_created_at"
    t.index ["user_id"], name: "index_chat_messages_on_user_id"
  end

  create_table "condition_logs", force: :cascade do |t|
    t.integer "available_time", null: false
    t.datetime "created_at", null: false
    t.date "date", null: false
    t.integer "energy_level", null: false
    t.integer "motivation", null: false
    t.text "notes"
    t.integer "sleep_quality", null: false
    t.jsonb "soreness", default: {}
    t.integer "stress_level", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["user_id", "date"], name: "index_condition_logs_on_user_id_and_date"
    t.index ["user_id"], name: "index_condition_logs_on_user_id"
  end

  create_table "exercises", force: :cascade do |t|
    t.boolean "active", default: true
    t.boolean "ai_generated", default: false
    t.boolean "bpm_compatible", default: true
    t.text "common_mistakes"
    t.datetime "created_at", null: false
    t.text "description"
    t.integer "difficulty", default: 1
    t.string "display_name"
    t.boolean "dropset_compatible", default: false
    t.string "english_name", null: false
    t.string "equipment", default: [], array: true
    t.string "fitness_factors", default: [], array: true
    t.text "form_tips"
    t.integer "min_level", default: 1
    t.string "movement_pattern"
    t.string "muscle_group", null: false
    t.string "name", null: false
    t.string "rom_options", default: ["full"], array: true
    t.string "secondary_muscles", default: [], array: true
    t.integer "sort_order", default: 0
    t.boolean "superset_compatible", default: true
    t.boolean "tabata_compatible", default: true
    t.datetime "updated_at", null: false
    t.jsonb "variations", default: {}
    t.jsonb "video_references", default: [], null: false
    t.index ["active"], name: "index_exercises_on_active"
    t.index ["ai_generated"], name: "index_exercises_on_ai_generated"
    t.index ["difficulty"], name: "index_exercises_on_difficulty"
    t.index ["english_name"], name: "index_exercises_on_english_name", unique: true
    t.index ["equipment"], name: "index_exercises_on_equipment", using: :gin
    t.index ["fitness_factors"], name: "index_exercises_on_fitness_factors", using: :gin
    t.index ["muscle_group"], name: "index_exercises_on_muscle_group"
    t.index ["name"], name: "index_exercises_on_name", unique: true
    t.index ["video_references"], name: "index_exercises_on_video_references", using: :gin
  end

  create_table "fitness_knowledge_chunks", force: :cascade do |t|
    t.text "content", null: false
    t.text "content_original"
    t.datetime "created_at", null: false
    t.string "difficulty_level"
    t.string "exercise_name"
    t.string "knowledge_type", null: false
    t.string "language", default: "ko", null: false
    t.jsonb "metadata", default: {}
    t.string "muscle_group"
    t.text "summary"
    t.integer "timestamp_end"
    t.integer "timestamp_start"
    t.datetime "updated_at", null: false
    t.bigint "youtube_video_id", null: false
    t.index ["difficulty_level"], name: "index_fitness_knowledge_chunks_on_difficulty_level"
    t.index ["exercise_name"], name: "index_fitness_knowledge_chunks_on_exercise_name"
    t.index ["knowledge_type"], name: "index_fitness_knowledge_chunks_on_knowledge_type"
    t.index ["language"], name: "index_fitness_knowledge_chunks_on_language"
    t.index ["muscle_group"], name: "index_fitness_knowledge_chunks_on_muscle_group"
    t.index ["youtube_video_id"], name: "index_fitness_knowledge_chunks_on_youtube_video_id"
  end

  create_table "fitness_test_submissions", force: :cascade do |t|
    t.jsonb "analyses", default: {}, null: false
    t.integer "assigned_level"
    t.string "assigned_tier"
    t.datetime "completed_at"
    t.datetime "created_at", null: false
    t.string "error_message"
    t.jsonb "evaluation_result", default: {}
    t.integer "fitness_score"
    t.string "job_id", null: false
    t.datetime "started_at"
    t.string "status", default: "pending", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.jsonb "videos", default: [], null: false
    t.index ["job_id"], name: "index_fitness_test_submissions_on_job_id", unique: true
    t.index ["status"], name: "index_fitness_test_submissions_on_status"
    t.index ["user_id", "created_at"], name: "index_fitness_test_submissions_on_user_id_and_created_at"
    t.index ["user_id"], name: "index_fitness_test_submissions_on_user_id"
  end

  create_table "level_test_verifications", force: :cascade do |t|
    t.text "ai_feedback"
    t.datetime "completed_at"
    t.datetime "created_at", null: false
    t.integer "current_level", null: false
    t.jsonb "exercises", default: [], null: false
    t.integer "new_level"
    t.boolean "passed", default: false
    t.datetime "started_at"
    t.string "status", default: "pending", null: false
    t.integer "target_level", null: false
    t.string "test_id", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["created_at"], name: "index_level_test_verifications_on_created_at"
    t.index ["test_id"], name: "index_level_test_verifications_on_test_id", unique: true
    t.index ["user_id", "status"], name: "index_level_test_verifications_on_user_id_and_status"
    t.index ["user_id"], name: "index_level_test_verifications_on_user_id"
  end

  create_table "onboarding_analytics", force: :cascade do |t|
    t.jsonb "collected_info", default: {}
    t.boolean "completed", default: false
    t.string "completion_reason"
    t.jsonb "conversation_log", default: []
    t.datetime "created_at", null: false
    t.string "prompt_version"
    t.string "session_id", null: false
    t.integer "time_to_complete_seconds"
    t.integer "turn_count", default: 0
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["completed"], name: "index_onboarding_analytics_on_completed"
    t.index ["created_at"], name: "index_onboarding_analytics_on_created_at"
    t.index ["prompt_version"], name: "index_onboarding_analytics_on_prompt_version"
    t.index ["session_id"], name: "index_onboarding_analytics_on_session_id", unique: true
    t.index ["user_id"], name: "index_onboarding_analytics_on_user_id"
  end

  create_table "routine_exercises", force: :cascade do |t|
    t.integer "bpm"
    t.datetime "created_at", null: false
    t.string "exercise_name", null: false
    t.text "how_to"
    t.integer "order_index", null: false
    t.text "purpose"
    t.string "range_of_motion"
    t.integer "reps"
    t.integer "rest_duration_seconds"
    t.integer "sets"
    t.string "target_muscle"
    t.datetime "updated_at", null: false
    t.decimal "weight", precision: 8, scale: 2
    t.string "weight_description"
    t.bigint "workout_routine_id", null: false
    t.index ["exercise_name", "target_muscle"], name: "index_routine_exercises_on_exercise_name_and_target_muscle"
    t.index ["workout_routine_id", "order_index"], name: "index_routine_exercises_on_workout_routine_id_and_order_index"
  end

  create_table "user_profiles", force: :cascade do |t|
    t.decimal "body_fat_percentage", precision: 5, scale: 2
    t.datetime "created_at", null: false
    t.string "current_level"
    t.integer "day_number", default: 1
    t.jsonb "fitness_factors", default: {}
    t.string "fitness_goal"
    t.datetime "form_onboarding_completed_at"
    t.decimal "height", precision: 5, scale: 2
    t.datetime "last_level_test_at"
    t.datetime "level_assessed_at"
    t.jsonb "max_lifts", default: {}
    t.integer "numeric_level", default: 1
    t.datetime "onboarding_completed_at"
    t.date "program_start_date"
    t.integer "total_workouts_completed", default: 0
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.integer "week_number", default: 1
    t.decimal "weight", precision: 5, scale: 2
    t.index ["numeric_level"], name: "index_user_profiles_on_numeric_level"
    t.index ["user_id"], name: "index_user_profiles_on_user_id", unique: true
  end

  create_table "users", force: :cascade do |t|
    t.string "apple_user_id"
    t.datetime "created_at", null: false
    t.string "email", null: false
    t.string "name"
    t.string "password_digest"
    t.datetime "updated_at", null: false
    t.index ["apple_user_id"], name: "index_users_on_apple_user_id", unique: true
    t.index ["email"], name: "index_users_on_email", unique: true
  end

  create_table "workout_feedbacks", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.text "feedback", null: false
    t.string "feedback_type", null: false
    t.integer "rating", null: false
    t.bigint "routine_id"
    t.jsonb "suggestions", default: []
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.bigint "workout_record_id"
    t.boolean "would_recommend", default: true, null: false
    t.index ["routine_id"], name: "index_workout_feedbacks_on_routine_id"
    t.index ["user_id"], name: "index_workout_feedbacks_on_user_id"
    t.index ["workout_record_id"], name: "index_workout_feedbacks_on_workout_record_id"
  end

  create_table "workout_records", force: :cascade do |t|
    t.integer "average_heart_rate"
    t.integer "calories_burned"
    t.string "completion_status", default: "COMPLETED", null: false
    t.datetime "created_at", null: false
    t.datetime "date", null: false
    t.integer "perceived_exertion", null: false
    t.bigint "routine_id"
    t.integer "total_duration", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.bigint "workout_session_id"
    t.index ["user_id", "date"], name: "index_workout_records_on_user_id_and_date"
    t.index ["user_id"], name: "index_workout_records_on_user_id"
    t.index ["workout_session_id"], name: "index_workout_records_on_workout_session_id"
  end

  create_table "workout_routines", force: :cascade do |t|
    t.datetime "completed_at"
    t.datetime "created_at", null: false
    t.integer "day_number", null: false
    t.string "day_of_week"
    t.integer "estimated_duration"
    t.datetime "generated_at", null: false
    t.boolean "is_completed", default: false
    t.string "level", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.integer "week_number", null: false
    t.string "workout_type"
    t.index ["user_id", "is_completed"], name: "index_workout_routines_on_user_id_and_is_completed"
    t.index ["user_id", "level", "week_number", "day_number"], name: "idx_workout_routines_on_user_level_week_day"
  end

  create_table "workout_sessions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "end_time"
    t.string "name"
    t.text "notes"
    t.string "source", default: "app"
    t.datetime "start_time", null: false
    t.string "status", default: "pending"
    t.integer "total_duration"
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["source"], name: "index_workout_sessions_on_source"
    t.index ["status"], name: "index_workout_sessions_on_status"
    t.index ["user_id", "start_time"], name: "index_workout_sessions_on_user_id_and_start_time"
  end

  create_table "workout_sets", force: :cascade do |t|
    t.string "client_id"
    t.datetime "created_at", null: false
    t.integer "duration_seconds"
    t.string "exercise_name", null: false
    t.text "notes"
    t.integer "reps"
    t.integer "rpe"
    t.integer "set_number"
    t.string "source", default: "app"
    t.string "target_muscle"
    t.datetime "updated_at", null: false
    t.decimal "weight", precision: 8, scale: 2
    t.string "weight_unit", default: "kg"
    t.bigint "workout_session_id", null: false
    t.index ["client_id"], name: "index_workout_sets_on_client_id", unique: true
    t.index ["source"], name: "index_workout_sets_on_source"
    t.index ["target_muscle"], name: "index_workout_sets_on_target_muscle"
    t.index ["workout_session_id", "exercise_name"], name: "index_workout_sets_on_workout_session_id_and_exercise_name"
  end

  create_table "youtube_channels", force: :cascade do |t|
    t.boolean "active", default: true
    t.string "channel_id", null: false
    t.datetime "created_at", null: false
    t.text "description"
    t.string "handle", null: false
    t.string "language", default: "ko", null: false
    t.datetime "last_analyzed_at"
    t.datetime "last_synced_at"
    t.string "name", null: false
    t.integer "subscriber_count"
    t.string "thumbnail_url"
    t.datetime "updated_at", null: false
    t.string "url", null: false
    t.integer "video_count"
    t.index ["active"], name: "index_youtube_channels_on_active"
    t.index ["channel_id"], name: "index_youtube_channels_on_channel_id", unique: true
    t.index ["handle"], name: "index_youtube_channels_on_handle", unique: true
    t.index ["language"], name: "index_youtube_channels_on_language"
  end

  create_table "youtube_videos", force: :cascade do |t|
    t.text "analysis_error"
    t.string "analysis_status", default: "pending"
    t.datetime "analyzed_at"
    t.string "category"
    t.datetime "created_at", null: false
    t.text "description"
    t.string "difficulty_level"
    t.integer "duration_seconds"
    t.string "language"
    t.integer "like_count"
    t.datetime "published_at"
    t.jsonb "raw_analysis", default: {}
    t.string "thumbnail_url"
    t.string "title", null: false
    t.text "transcript"
    t.datetime "updated_at", null: false
    t.string "video_id", null: false
    t.integer "view_count"
    t.bigint "youtube_channel_id", null: false
    t.index ["analysis_status"], name: "index_youtube_videos_on_analysis_status"
    t.index ["category"], name: "index_youtube_videos_on_category"
    t.index ["published_at"], name: "index_youtube_videos_on_published_at"
    t.index ["video_id"], name: "index_youtube_videos_on_video_id", unique: true
    t.index ["youtube_channel_id"], name: "index_youtube_videos_on_youtube_channel_id"
  end

  add_foreign_key "chat_messages", "users"
  add_foreign_key "condition_logs", "users"
  add_foreign_key "fitness_knowledge_chunks", "youtube_videos"
  add_foreign_key "fitness_test_submissions", "users"
  add_foreign_key "level_test_verifications", "users"
  add_foreign_key "onboarding_analytics", "users"
  add_foreign_key "routine_exercises", "workout_routines"
  add_foreign_key "user_profiles", "users"
  add_foreign_key "workout_feedbacks", "users"
  add_foreign_key "workout_records", "users"
  add_foreign_key "workout_records", "workout_sessions"
  add_foreign_key "workout_routines", "users"
  add_foreign_key "workout_sessions", "users"
  add_foreign_key "workout_sets", "workout_sessions"
  add_foreign_key "youtube_videos", "youtube_channels"
end
