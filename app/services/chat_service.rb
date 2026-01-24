# frozen_string_literal: true

# ChatService: Core service for conversational AI trainer
# Handles intent classification and routing to appropriate handlers
class ChatService
  # Fitness-related keywords for off-topic detection
  FITNESS_KEYWORDS = %w[
    운동 루틴 세트 횟수 무게 킬로 킬로그램
    벤치 스쿼트 데드 풀업 푸시업 런지 플랭크
    덤벨 바벨 케틀벨 머신 케이블
    가슴 어깨 하체 코어 복근 이두 삼두 전완
    컨디션 피곤 아파 통증 회복 스트레칭 워밍업
    승급 최고 평균 볼륨
    휴식 쉬는날 오프데이
    단백질 식단 영양 보충제
    근력 근육 체력 유산소 무산소
    트레이닝 웨이트 헬스 짐
  ].freeze

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

  # Intent trigger keywords
  INTENT_KEYWORDS = {
    generate_routine: %w[루틴 만들어 생성 추천해 오늘의],
    check_condition: %w[컨디션 피곤 지쳤 힘들 아파 통증 좋아 괜찮 상태],
    submit_feedback: %w[힘들었 어려웠 쉬웠 좋았 별로 피드백 느낌]
  }.freeze

  # Off-topic response templates
  OFF_TOPIC_RESPONSES = [
    "저는 운동 트레이너예요! 💪 운동 관련 질문을 해주세요.",
    "운동 기록, 루틴 생성, 컨디션 체크를 도와드릴 수 있어요!",
    "오늘 운동은 하셨나요? 루틴을 만들어드릴까요?",
    "운동에 관해 궁금한 게 있으시면 물어보세요! 🏋️"
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
    # 2. Random chance (10%) on general fitness messages to be proactive
    # 3. User completed a workout recently
    message_lower = message.downcase

    # Check for explicit promotion-related keywords
    promotion_keywords = %w[승급 레벨 레벨업 level 등급]
    return true if promotion_keywords.any? { |kw| message_lower.include?(kw) }

    # Random proactive check (10% chance on fitness-related messages)
    return true if fitness_related? && rand < 0.1

    false
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
  # Intent Classification
  # ============================================

  def classify_intent
    # 1. Check for off-topic (non-fitness related)
    return :off_topic unless fitness_related?

    # 2. Try rule-based classification first
    intent = rule_based_classification
    return intent if intent

    # 3. Fallback to general chat (will use Haiku)
    :general_chat
  end

  def fitness_related?
    message_lower = message.downcase
    # Must have actual fitness keywords, not just time keywords like "오늘"
    FITNESS_KEYWORDS.any? { |kw| message_lower.include?(kw) } ||
      matches_record_pattern? ||
      matches_explicit_query_pattern?
  end

  def rule_based_classification
    # Check record pattern first (most specific)
    return :record_exercise if matches_record_pattern?

    message_lower = message.downcase

    # Check specific intent keywords BEFORE query pattern
    # This ensures "오늘의 루틴 만들어줘" is GENERATE_ROUTINE, not QUERY_RECORDS
    INTENT_KEYWORDS.each do |intent, keywords|
      return intent if keywords.any? { |kw| message_lower.include?(kw) }
    end

    # Check query pattern only if it has actual query triggers (not just time keywords)
    return :query_records if matches_explicit_query_pattern?

    nil
  end

  def matches_record_pattern?
    RECORD_PATTERNS.any? { |pattern| message.match?(pattern) }
  end

  def matches_query_pattern?
    message_lower = message.downcase
    has_time_keyword = QUERY_KEYWORDS[:time_range].keys.any? { |kw| message_lower.include?(kw) }
    has_query_trigger = QUERY_KEYWORDS[:query_triggers].any? { |kw| message_lower.include?(kw) }
    has_time_keyword || has_query_trigger
  end

  # More strict version: requires actual query trigger words, not just time keywords
  def matches_explicit_query_pattern?
    message_lower = message.downcase
    QUERY_KEYWORDS[:query_triggers].any? { |kw| message_lower.include?(kw) }
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
    when :generate_routine
      handle_generate_routine
    when :submit_feedback
      handle_submit_feedback
    when :general_chat
      handle_general_chat
    when :off_topic
      handle_off_topic
    else
      error_response("알 수 없는 요청입니다.")
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

  # Handle routine generation (AI - Sonnet)
  def handle_generate_routine
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
  def handle_off_topic
    success_response(
      message: OFF_TOPIC_RESPONSES.sample,
      intent: "OFF_TOPIC",
      data: nil
    )
  end

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
