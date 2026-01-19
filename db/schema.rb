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

ActiveRecord::Schema[8.1].define(version: 2025_01_19_000006) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"

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
    t.decimal "height", precision: 5, scale: 2
    t.datetime "last_level_test_at"
    t.datetime "level_assessed_at"
    t.jsonb "max_lifts", default: {}
    t.integer "numeric_level", default: 1
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
    t.datetime "created_at", null: false
    t.string "email", null: false
    t.string "name"
    t.string "password_digest", null: false
    t.datetime "updated_at", null: false
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
    t.datetime "start_time", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["user_id", "start_time"], name: "index_workout_sessions_on_user_id_and_start_time"
  end

  create_table "workout_sets", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.integer "duration_seconds"
    t.string "exercise_name", null: false
    t.text "notes"
    t.integer "reps"
    t.integer "rpe"
    t.integer "set_number"
    t.string "target_muscle"
    t.datetime "updated_at", null: false
    t.decimal "weight", precision: 8, scale: 2
    t.string "weight_unit", default: "kg"
    t.bigint "workout_session_id", null: false
    t.index ["target_muscle"], name: "index_workout_sets_on_target_muscle"
    t.index ["workout_session_id", "exercise_name"], name: "index_workout_sets_on_workout_session_id_and_exercise_name"
  end

  add_foreign_key "condition_logs", "users"
  add_foreign_key "routine_exercises", "workout_routines"
  add_foreign_key "user_profiles", "users"
  add_foreign_key "workout_feedbacks", "users"
  add_foreign_key "workout_records", "users"
  add_foreign_key "workout_records", "workout_sessions"
  add_foreign_key "workout_routines", "users"
  add_foreign_key "workout_sessions", "users"
  add_foreign_key "workout_sets", "workout_sessions"
end
