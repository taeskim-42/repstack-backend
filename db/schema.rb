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

ActiveRecord::Schema[8.0].define(version: 2024_12_27_000006) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "plpgsql"

  create_table "users", force: :cascade do |t|
    t.string "email", null: false
    t.string "name"
    t.string "password_digest", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["email"], name: "index_users_on_email", unique: true
  end

  create_table "user_profiles", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.decimal "height", precision: 5, scale: 2
    t.decimal "weight", precision: 5, scale: 2
    t.decimal "body_fat_percentage", precision: 5, scale: 2
    t.string "current_level"
    t.integer "week_number", default: 1
    t.integer "day_number", default: 1
    t.string "fitness_goal"
    t.date "program_start_date"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["user_id"], name: "index_user_profiles_on_user_id", unique: true
  end

  create_table "workout_sessions", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.string "name"
    t.datetime "start_time", null: false
    t.datetime "end_time"
    t.text "notes"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["user_id", "start_time"], name: "index_workout_sessions_on_user_id_and_start_time"
  end

  create_table "workout_sets", force: :cascade do |t|
    t.bigint "workout_session_id", null: false
    t.string "exercise_name", null: false
    t.decimal "weight", precision: 8, scale: 2
    t.string "weight_unit", default: "kg"
    t.integer "reps"
    t.integer "duration_seconds"
    t.text "notes"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["workout_session_id", "exercise_name"], name: "index_workout_sets_on_workout_session_id_and_exercise_name"
  end

  create_table "workout_routines", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.string "level", null: false
    t.integer "week_number", null: false
    t.integer "day_number", null: false
    t.string "workout_type"
    t.string "day_of_week"
    t.integer "estimated_duration"
    t.boolean "is_completed", default: false
    t.datetime "completed_at"
    t.datetime "generated_at", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["user_id", "level", "week_number", "day_number"], name: "idx_workout_routines_on_user_level_week_day"
    t.index ["user_id", "is_completed"], name: "index_workout_routines_on_user_id_and_is_completed"
  end

  create_table "routine_exercises", force: :cascade do |t|
    t.bigint "workout_routine_id", null: false
    t.string "exercise_name", null: false
    t.string "target_muscle"
    t.integer "order_index", null: false
    t.integer "sets"
    t.integer "reps"
    t.decimal "weight", precision: 8, scale: 2
    t.string "weight_description"
    t.integer "bpm"
    t.integer "rest_duration_seconds"
    t.string "range_of_motion"
    t.text "how_to"
    t.text "purpose"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["workout_routine_id", "order_index"], name: "index_routine_exercises_on_workout_routine_id_and_order_index"
    t.index ["exercise_name", "target_muscle"], name: "index_routine_exercises_on_exercise_name_and_target_muscle"
  end

  add_foreign_key "user_profiles", "users"
  add_foreign_key "workout_sessions", "users"
  add_foreign_key "workout_sets", "workout_sessions"
  add_foreign_key "workout_routines", "users"
  add_foreign_key "routine_exercises", "workout_routines"
end