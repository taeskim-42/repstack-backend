# frozen_string_literal: true

# ChatService: Core service for conversational AI trainer
# Handles intent classification and routing to appropriate handlers
class ChatService
  # Record patterns for exercise recording
  RECORD_PATTERNS = [
    # "벤치프레스 60kg 8회" or "벤치프레스 60킬로 8회"
    /(?<exercise>.+?)\s*(?<weight>\d+(?:\.\d+)?)\s*(?:kg|킬로|킬로그램)\s*(?<reps>\d+)\s*(?:회|개|번|reps?)/i,
    # "벤치프레스 60kg 8회 4세트"
    /(?<exercise>.+?)\s*(?<weight>\d+(?:\.\d+)?)\s*(?:kg|킬로)\s*(?<reps>\d+)\s*(?:회|개|번)\s*(?<sets>\d+)\s*세트/i,
    # "스쿼트 10회 4세트"
    /(?<exercise>.+?)\s*(?<reps>\d+)\s*(?:회|개|번)\s*(?<sets>\d+)\s*세트/i,
    # "데드리프트 4세트 8회"
    /(?<exercise>.+?)\s*(?<sets>\d+)\s*세트\s*(?<reps>\d+)\s*(?:회|개|번)/i,
    # "풀업 8개" (no weight)
    /(?<exercise>.+?)\s*(?<reps>\d+)\s*(?:회|개|번)/i
  ].freeze

  # Query keywords for record lookup
  QUERY_KEYWORDS = {
    time_range: {
      "오늘" => :today,
      "어제" => :yesterday,
      "이번주" => :this_week,
      "지난주" => :last_week,
      "이번달" => :this_month,
      "지난달" => :last_month,
      "최근" => :recent
    },
    aggregation: {
      "최고" => :max,
      "최대" => :max,
      "평균" => :avg,
      "총" => :sum,
      "몇 번" => :count,
      "몇번" => :count
    },
    query_triggers: %w[기록 언제 얼마나 몇 조회 알려줘 보여줘]
  }.freeze

  # Valid intents for classification
  VALID_INTENTS = %w[
    record_exercise
    query_records
    check_condition
    generate_routine
    add_to_routine
    submit_feedback
    general_chat
  ].freeze

  # Patterns for adding exercise to routine
  ADD_TO_ROUTINE_PATTERNS = [
    # "랫풀다운 루틴에 추가해줘" or "랫풀다운 추가해줘"
    /(?<exercise>.+?)\s*(?:루틴에\s*)?추가해\s*(?:줘|주세요|줄래)?/i,
    # "루틴에 랫풀다운 추가"
    /루틴에\s*(?<exercise>.+?)\s*추가/i
  ].freeze


  class << self
    def process(user:, message:, routine_id: nil, session_id: nil)
      new(user: user, message: message, routine_id: routine_id, session_id: session_id).process
    end
  end

  def initialize(user:, message:, routine_id: nil, session_id: nil)
    @user = user
    @message = message.strip
    @routine_id = routine_id
    @session_id = session_id
  end

  def process
    # Check if user needs level assessment first (new user onboarding)
    if needs_level_assessment?
      return handle_level_assessment
    end

    # Check if user is eligible for promotion (proactive notification)
    # Only check periodically to avoid spamming
    if should_check_promotion? && eligible_for_promotion?
      return handle_promotion_eligible
    end

    intent = classify_intent
    handle_intent(intent)
  rescue StandardError => e
    Rails.logger.error("ChatService error: #{e.message}")
    Rails.logger.error(e.backtrace.first(5).join("\n"))
    error_response("처리 중 오류가 발생했습니다: #{e.message}")
  end

  private

  attr_reader :user, :message, :routine_id, :session_id

  # ============================================
  # Level Assessment (New User Onboarding)
  # ============================================

  def needs_level_assessment?
    AiTrainer::LevelAssessmentService.needs_assessment?(user)
  end

  def handle_level_assessment
    result = AiTrainer::LevelAssessmentService.assess(user: user, message: message)

    if result[:success]
      success_response(
        message: result[:message],
        intent: "LEVEL_ASSESSMENT",
        data: {
          is_complete: result[:is_complete],
          assessment: result[:assessment]
        }
      )
    else
      error_response(result[:error] || "수준 파악에 실패했어요.")
    end
  end

  # ============================================
  # Promotion Eligibility Check
  # ============================================

  def should_check_promotion?
    # Only check promotion eligibility on certain triggers:
    # 1. User asks about level/promotion
    # 2. Random chance (5%) to be proactive
    message_lower = message.downcase

    # Check for explicit promotion-related keywords
    promotion_keywords = %w[승급 레벨 레벨업 level 등급]
    return true if promotion_keywords.any? { |kw| message_lower.include?(kw) }

    # Random proactive check (5% chance)
    rand < 0.05
  end

  def eligible_for_promotion?
    service = AiTrainer::LevelTestService.new(user: user)
    result = service.evaluate_promotion_readiness

    # Store result for use in handler
    @promotion_result = result
    result[:eligible]
  end

  def handle_promotion_eligible
    result = @promotion_result
    current_level = result[:current_level]
    target_level = result[:target_level]
    target_tier = AiTrainer::Constants.tier_for_level(target_level)

    # Build encouraging message
    message = build_promotion_message(result)

    success_response(
      message: message,
      intent: "PROMOTION_ELIGIBLE",
      data: {
        current_level: current_level,
        target_level: target_level,
        target_tier: target_tier,
        estimated_1rms: result[:estimated_1rms],
        required_1rms: result[:required_1rms],
        exercise_results: format_exercise_results(result[:exercise_results])
      }
    )
  end

  def build_promotion_message(result)
    target_level = result[:target_level]
    target_tier = AiTrainer::Constants.tier_for_level(target_level)
    tier_korean = tier_to_korean(target_tier)

    <<~MESSAGE.strip
      🎯 운동 기록을 분석해보니 실력이 많이 늘었네요!

      레벨 #{target_level} (#{tier_korean}) 승급 조건을 충족했어요. 💪

      승급 테스트에 도전하시겠어요?
    MESSAGE
  end

  def tier_to_korean(tier)
    case tier
    when "beginner" then "초급"
    when "intermediate" then "중급"
    when "advanced" then "고급"
    else tier
    end
  end

  def format_exercise_results(results)
    return nil unless results

    results.transform_values do |data|
      {
        estimated_1rm: data[:estimated_1rm],
        required: data[:required],
        status: data[:status].to_s,
        gap: data[:gap],
        surplus: data[:surplus]
      }
    end
  end

  # ============================================
  # Intent Classification (Claude-powered)
  # ============================================

  def classify_intent
    # 1. Check record pattern first (regex is more accurate for structured input)
    return :record_exercise if matches_record_pattern?

    # 2. Use Claude for all other intent classification
    classify_intent_with_claude
  end

  def classify_intent_with_claude
    prompt = build_intent_classification_prompt

    response = AiTrainer::LlmGateway.chat(
      prompt: prompt,
      task: :intent_classification
    )

    if response[:success] && response[:content].present?
      parse_intent_response(response[:content])
    else
      Rails.logger.warn("Intent classification failed, defaulting to general_chat")
      :general_chat
    end
  rescue StandardError => e
    Rails.logger.error("Intent classification error: #{e.message}")
    :general_chat
  end

  def build_intent_classification_prompt
    <<~PROMPT
      사용자 메시지의 의도를 분류하세요.

      메시지: "#{message}"

      가능한 의도:
      - record_exercise: 운동 기록 (예: "벤치프레스 60kg 8회", "스쿼트 10개 했어")
      - query_records: 기록 조회 (예: "지난주 기록 보여줘", "벤치 최고 무게 얼마야?")
      - check_condition: 컨디션/상태 표현 (예: "오늘 컨디션 좋아", "피곤해", "구웃", "ㅠㅠ", "최고", "별로")
      - generate_routine: 루틴 생성의 **명시적 요청**만 해당 (예: "루틴 만들어줘", "오늘 운동 짜줘", "루틴 추천해줘")
        * "~하고 싶다", "~키우고 싶다"는 희망사항이므로 general_chat
        * "~알려줘", "~방법" 같은 질문은 general_chat
      - add_to_routine: 기존 루틴에 운동 추가 (예: "랫풀다운 추가해줘")
      - submit_feedback: 운동 피드백 (예: "오늘 운동 힘들었어", "쉬웠어")
      - general_chat: 일반 대화, 질문, 희망사항 표현 (예: "벤치프레스 자세 알려줘", "등근육 키우고 싶어", "스쿼트 방법")

      ⚠️ 확실하지 않으면 general_chat으로 분류하세요.
      한 단어로만 응답하세요 (예: general_chat)
    PROMPT
  end

  def parse_intent_response(content)
    intent = content.strip.downcase.gsub(/[^a-z_]/, "")

    if VALID_INTENTS.include?(intent)
      intent.to_sym
    else
      Rails.logger.warn("Unknown intent from Claude: #{content}, defaulting to general_chat")
      :general_chat
    end
  end

  def matches_record_pattern?
    RECORD_PATTERNS.any? { |pattern| message.match?(pattern) }
  end

  # ============================================
  # Intent Handlers
  # ============================================

  def handle_intent(intent)
    case intent
    when :record_exercise
      handle_record_exercise
    when :query_records
      handle_query_records
    when :check_condition
      handle_check_condition
    when :add_to_routine
      handle_add_to_routine
    when :generate_routine
      handle_generate_routine
    when :submit_feedback
      handle_submit_feedback
    when :general_chat
      handle_general_chat
    else
      handle_general_chat # Fallback to AI for unknown intents
    end
  end

  # Handle exercise recording (no AI - regex parsing)
  def handle_record_exercise
    parsed = parse_exercise_record
    return error_response("운동 기록을 파싱하지 못했어요. 예: '벤치프레스 60kg 8회'") unless parsed

    result = ChatRecordService.record_exercise(
      user: user,
      exercise_name: parsed[:exercise],
      weight: parsed[:weight],
      reps: parsed[:reps],
      sets: parsed[:sets] || 1
    )

    if result[:success]
      record_item = {
        exercise_name: parsed[:exercise],
        weight: parsed[:weight],
        reps: parsed[:reps],
        sets: parsed[:sets] || 1,
        recorded_at: Time.current.iso8601
      }

      success_response(
        message: format_record_message(parsed),
        intent: "RECORD_EXERCISE",
        data: { records: [ record_item ] }
      )
    else
      error_response(result[:error] || "기록 저장에 실패했어요.")
    end
  end

  # Handle record queries (no AI - DB query)
  def handle_query_records
    query_params = parse_query_params
    result = ChatQueryService.query_records(user: user, params: query_params)

    if result[:success]
      success_response(
        message: result[:interpretation] || "조회 결과입니다:",
        intent: "QUERY_RECORDS",
        data: {
          records: result[:records],
          summary: result[:summary]
        }
      )
    else
      error_response(result[:error] || "기록 조회에 실패했어요.")
    end
  end

  # Handle condition check (AI - Sonnet)
  def handle_check_condition
    # Reuse existing checkConditionFromVoice logic
    result = AiTrainer::ConditionService.analyze_from_text(
      user: user,
      text: message
    )

    if result[:success]
      success_response(
        message: result[:message] || "컨디션을 확인했어요!",
        intent: "CHECK_CONDITION",
        data: {
          condition: {
            score: result[:score],
            status: result[:status],
            adaptations: result[:adaptations],
            recommendations: result[:recommendations]
          }
        }
      )
    else
      error_response(result[:error] || "컨디션 분석에 실패했어요.")
    end
  end

  # Handle adding exercise to existing routine
  def handle_add_to_routine
    # Parse exercise name from message
    exercise_name = parse_exercise_for_add
    return error_response("어떤 운동을 추가할지 말씀해 주세요. 예: '랫풀다운 추가해줘'") unless exercise_name

    # Find active (in-progress) routine
    active_routine = find_active_routine
    unless active_routine
      # No active routine - create new one instead
      return handle_generate_routine_with_exercise(exercise_name)
    end

    # Add exercise to routine
    result = add_exercise_to_routine(active_routine, exercise_name)

    if result[:success]
      success_response(
        message: "#{exercise_name}을(를) 루틴에 추가했어요! 💪",
        intent: "ADD_TO_ROUTINE",
        data: {
          routine: result[:routine],
          added_exercise: result[:added_exercise]
        }
      )
    else
      error_response(result[:error] || "운동 추가에 실패했어요.")
    end
  end

  def parse_exercise_for_add
    ADD_TO_ROUTINE_PATTERNS.each do |pattern|
      match = message.match(pattern)
      return match[:exercise].strip if match && match[:exercise].present?
    end

    # Fallback: extract text before "추가"
    if message.include?("추가")
      parts = message.split(/추가/)
      candidate = parts.first.strip.gsub(/루틴에|지금|현재/, "").strip
      return candidate if candidate.present? && candidate.length >= 2
    end

    nil
  end

  def find_active_routine
    # Find today's incomplete routine
    user.workout_routines
        .where(is_completed: false)
        .where("DATE(created_at) = ?", Date.current)
        .order(created_at: :desc)
        .first
  end

  def add_exercise_to_routine(routine, exercise_name)
    # Determine order index (add to end)
    order_index = (routine.routine_exercises.maximum(:order_index) || -1) + 1

    # Infer target muscle
    target_muscle = infer_target_muscle(exercise_name)

    # Create exercise
    exercise = routine.routine_exercises.create!(
      exercise_name: exercise_name,
      order_index: order_index,
      sets: 3,
      reps: 10,
      target_muscle: target_muscle,
      rest_duration_seconds: 60
    )

    {
      success: true,
      routine: routine.reload,
      added_exercise: exercise
    }
  rescue ActiveRecord::RecordInvalid => e
    { success: false, error: "운동 추가 실패: #{e.message}" }
  end

  def infer_target_muscle(exercise_name)
    name_lower = exercise_name.downcase

    muscle_mappings = {
      "chest" => %w[벤치 푸시업 체스트 플라이 딥스 가슴],
      "back" => %w[풀업 로우 렛풀 랫풀 데드리프트 턱걸이 등 광배],
      "shoulders" => %w[숄더 프레스 레이즈 어깨],
      "legs" => %w[스쿼트 런지 레그 프레스 컬 익스텐션 다리 하체],
      "arms" => %w[컬 바이셉 트라이셉 삼두 이두 팔],
      "core" => %w[플랭크 크런치 싯업 복근 코어 복부]
    }

    muscle_mappings.each do |muscle, keywords|
      return muscle if keywords.any? { |kw| name_lower.include?(kw) }
    end

    "other"
  end

  def handle_generate_routine_with_exercise(exercise_name)
    # Create new routine and add the requested exercise
    day_of_week = Date.current.cwday
    day_of_week = [day_of_week, 5].min

    routine = AiTrainer::RoutineService.generate(
      user: user,
      day_of_week: day_of_week
    )

    if routine
      # Add the requested exercise
      add_result = add_exercise_to_routine(routine, exercise_name)

      success_response(
        message: "진행 중인 루틴이 없어서 새 루틴을 만들고 #{exercise_name}을(를) 추가했어요! 💪",
        intent: "GENERATE_ROUTINE",
        data: {
          routine: add_result[:routine] || routine,
          added_exercise: add_result[:added_exercise]
        }
      )
    else
      error_response("루틴 생성에 실패했어요.")
    end
  end

  # Handle routine generation (AI - Sonnet)
  def handle_generate_routine
    # Check if there's already a routine for today
    existing_routine = user.workout_routines
                           .where(is_completed: false)
                           .where("DATE(created_at) = ?", Date.current)
                           .order(created_at: :desc)
                           .first

    if existing_routine
      # Don't create new routine if one already exists
      return success_response(
        message: "이미 오늘의 루틴이 있어요! 기존 루틴을 수정하거나 운동을 추가하시겠어요? 💪",
        intent: "EXISTING_ROUTINE",
        data: { routine: existing_routine }
      )
    end

    # Get today's day of week
    day_of_week = Date.current.cwday # 1=Monday, 7=Sunday
    day_of_week = [ day_of_week, 5 ].min # Cap at 5 (Friday)

    routine = AiTrainer::RoutineService.generate(
      user: user,
      day_of_week: day_of_week
    )

    if routine
      success_response(
        message: "오늘의 루틴을 만들었어요! 💪",
        intent: "GENERATE_ROUTINE",
        data: { routine: routine }
      )
    else
      error_response("루틴 생성에 실패했어요. 잠시 후 다시 시도해주세요.")
    end
  end

  # Handle feedback submission (AI - Sonnet)
  def handle_submit_feedback
    result = AiTrainer::FeedbackService.analyze_from_text(
      user: user,
      text: message,
      routine_id: routine_id
    )

    if result[:success]
      success_response(
        message: result[:message] || "피드백 감사해요! 다음 루틴에 반영할게요. 💡",
        intent: "SUBMIT_FEEDBACK",
        data: {
          feedback: {
            insights: result[:insights],
            adaptations: result[:adaptations],
            next_workout_recommendations: result[:next_workout_recommendations]
          }
        }
      )
    else
      error_response(result[:error] || "피드백 처리에 실패했어요.")
    end
  end

  # Handle general fitness chat (AI - Haiku for cost efficiency)
  def handle_general_chat
    result = AiTrainer::ChatService.general_chat(
      user: user,
      message: message
    )

    success_response(
      message: result[:message] || "무엇을 도와드릴까요?",
      intent: "GENERAL_CHAT",
      data: nil
    )
  end

  # Handle off-topic messages (no AI)
  # ============================================
  # Parsing Helpers
  # ============================================

  def parse_exercise_record
    RECORD_PATTERNS.each do |pattern|
      match = message.match(pattern)
      next unless match

      return {
        exercise: match[:exercise].strip,
        weight: match.names.include?("weight") ? match[:weight].to_f : nil,
        reps: match[:reps].to_i,
        sets: match.names.include?("sets") ? match[:sets].to_i : 1
      }
    end
    nil
  end

  def parse_query_params
    message_lower = message.downcase
    params = {}

    # Parse time range
    QUERY_KEYWORDS[:time_range].each do |keyword, value|
      if message_lower.include?(keyword)
        params[:time_range] = value
        break
      end
    end
    params[:time_range] ||= :recent

    # Parse aggregation
    QUERY_KEYWORDS[:aggregation].each do |keyword, value|
      if message_lower.include?(keyword)
        params[:aggregation] = value
        break
      end
    end

    # Try to extract exercise name (simple approach)
    # Look for common exercise names in the message
    exercise_names = %w[벤치프레스 벤치 스쿼트 데드리프트 데드 풀업 푸시업 런지 숄더프레스 로우]
    exercise_names.each do |name|
      if message_lower.include?(name)
        params[:exercise_name] = name
        break
      end
    end

    params
  end

  def format_record_message(parsed)
    parts = [ "기록했어요! #{parsed[:exercise]}" ]
    parts << "#{parsed[:weight]}kg" if parsed[:weight]
    parts << "#{parsed[:reps]}회"
    parts << "#{parsed[:sets]}세트" if parsed[:sets] && parsed[:sets] > 1
    parts.join(" ") + " 💪"
  end

  # ============================================
  # Response Helpers
  # ============================================

  def success_response(message:, intent:, data:)
    {
      success: true,
      message: message,
      intent: intent,
      data: data,
      error: nil
    }
  end

  def error_response(error_message)
    {
      success: false,
      message: nil,
      intent: nil,
      data: nil,
      error: error_message
    }
  end
end
