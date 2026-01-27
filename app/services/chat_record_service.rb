# frozen_string_literal: true

# ChatRecordService: Handles exercise recording from chat
# Creates workout sets in the appropriate session
# Uses AI to match user input (including typos) to correct exercise names
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
    # First, match the exercise name using AI
    matched_name = match_exercise_with_ai(exercise_name)

    ActiveRecord::Base.transaction do
      # Find or create active session
      session = find_or_create_active_session

      # Create workout sets
      created_sets = []
      sets.times do |i|
        set = session.workout_sets.create!(
          exercise_name: matched_name,
          weight: weight,
          reps: reps,
          set_number: next_set_number(session, matched_name),
          source: "chat"
        )
        created_sets << set
      end

      {
        success: true,
        session: session,
        sets: created_sets,
        matched_exercise: matched_name,
        original_input: exercise_name,
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

  # Use Claude AI to match user input to correct exercise name
  def match_exercise_with_ai(user_input)
    # Get all exercises from DB
    exercises = Exercise.active.pluck(:name, :english_name)
    exercise_list = exercises.map { |name, eng| "#{name} (#{eng})" }.join(", ")

    prompt = build_exercise_match_prompt(user_input, exercise_list)

    response = AiTrainer::LlmGateway.chat(
      prompt: prompt,
      task: :intent_classification # Fast, cheap model
    )

    if response[:success] && response[:content].present?
      matched = response[:content].strip
      # Verify it's a valid exercise name
      valid_names = exercises.map(&:first)
      return matched if valid_names.include?(matched)

      # Try to find partial match
      found = valid_names.find { |name| matched.include?(name) || name.include?(matched) }
      return found if found
    end

    # Fallback: try simple matching
    simple_match(user_input) || user_input
  rescue StandardError => e
    Rails.logger.warn("AI exercise matching failed: #{e.message}, using fallback")
    simple_match(user_input) || user_input
  end

  def build_exercise_match_prompt(user_input, exercise_list)
    <<~PROMPT
      사용자가 입력한 운동명을 정확한 운동명으로 매칭해주세요.
      오타, 줄임말, 영어, 비슷한 발음 모두 고려하세요.

      사용자 입력: "#{user_input}"

      가능한 운동 목록:
      #{exercise_list}

      위 목록에서 가장 적합한 운동의 한글 이름만 응답하세요.
      예시: 푸시업, 맨몸 스쿼트, 벤치프레스

      운동명만 응답 (설명 없이):
    PROMPT
  end

  # Simple fallback matching without AI
  def simple_match(name)
    name = name.strip.downcase

    # Common abbreviations and typos
    mappings = {
      "벤치" => "벤치프레스",
      "벤프" => "벤치프레스",
      "데드" => "데드리프트",
      "풀업" => "턱걸이",
      "친업" => "턱걸이",
      "스퀏" => "맨몸 스쿼트",
      "스쿼" => "맨몸 스쿼트",
      "스콱" => "맨몸 스쿼트",
      "스쿼트" => "맨몸 스쿼트",
      "숄프" => "덤벨 숄더프레스",
      "숄더" => "덤벨 숄더프레스",
      "렛풀" => "렛풀다운",
      "랫풀" => "렛풀다운",
      "푸쉬업" => "푸시업",
      "푸샵" => "푸시업",
      "플랭" => "플랭크",
      "런지" => "런지",
      "컬" => "덤벨컬",
      "바벨컬" => "바벨컬",
      "레그컬" => "레그컬"
    }

    # Try exact match
    return mappings[name] if mappings[name]

    # Try partial match
    mappings.each do |key, value|
      return value if name.include?(key)
    end

    nil
  end

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
    session.workout_sets.where(exercise_name: exercise_name).count + 1
  end
end
