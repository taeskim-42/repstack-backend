# frozen_string_literal: true

# ChatRecordService: Handles exercise recording from chat
# Creates workout sets in the appropriate session
class ChatRecordService
  class << self
    def record_exercise(user:, exercise_name:, weight:, reps:, sets: 1)
      new(user: user).record_exercise(
        exercise_name: exercise_name,
        weight: weight,
        reps: reps,
        sets: sets
      )
    end
  end

  def initialize(user:)
    @user = user
  end

  def record_exercise(exercise_name:, weight:, reps:, sets: 1)
    ActiveRecord::Base.transaction do
      # Find or create active session
      session = find_or_create_active_session

      # Create workout sets
      created_sets = []
      sets.times do |i|
        set = session.workout_sets.create!(
          exercise_name: normalize_exercise_name(exercise_name),
          weight: weight,
          reps: reps,
          set_number: next_set_number(session, exercise_name),
          source: "chat"
        )
        created_sets << set
      end

      {
        success: true,
        session: session,
        sets: created_sets,
        error: nil
      }
    end
  rescue ActiveRecord::RecordInvalid => e
    Rails.logger.error("ChatRecordService validation error: #{e.message}")
    { success: false, error: "기록 저장 실패: #{e.message}" }
  rescue StandardError => e
    Rails.logger.error("ChatRecordService error: #{e.message}")
    { success: false, error: "기록 저장 중 오류 발생" }
  end

  private

  attr_reader :user

  def find_or_create_active_session
    # Look for any active session (end_time is nil) - most important check
    active_session = user.workout_sessions.where(end_time: nil).order(created_at: :desc).first
    return active_session if active_session

    # Look for a recent session from today that's completed but we can use
    today_session = user.workout_sessions
                        .where("DATE(start_time) = ?", Date.current)
                        .where(source: "chat")
                        .order(created_at: :desc)
                        .first
    return today_session if today_session

    # Create a new "quick log" session with end_time set (so it's not "active")
    # This allows multiple quick log sessions per day
    now = Time.current
    user.workout_sessions.create!(
      name: "퀵 로그 - #{Date.current.strftime('%Y-%m-%d %H:%M')}",
      source: "chat",
      start_time: now,
      end_time: now + 1.hour, # Set end_time after start_time to pass validation
      status: "completed"
    )
  end

  def next_set_number(session, exercise_name)
    normalized_name = normalize_exercise_name(exercise_name)
    session.workout_sets.where(exercise_name: normalized_name).count + 1
  end

  def normalize_exercise_name(name)
    # Normalize common exercise name variations
    name = name.strip

    # Map common abbreviations/variations
    mappings = {
      "벤치" => "벤치프레스",
      "데드" => "데드리프트",
      "스퀏" => "스쿼트",
      "숄프" => "숄더프레스",
      "렛풀" => "렛풀다운"
    }

    mappings[name] || name
  end
end
