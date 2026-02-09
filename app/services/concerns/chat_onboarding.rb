# frozen_string_literal: true

# Extracted from ChatService: daily greeting, welcome message,
# level assessment, and today-routine triggers.
module ChatOnboarding
  extend ActiveSupport::Concern

  private

  # ============================================
  # Daily Greeting (AI First - All Users)
  # ============================================

  def needs_daily_greeting?
    # Only trigger on empty message or "start"/"시작"
    return false unless message.blank? || message == "시작" || message == "start"

    # Must have completed onboarding
    profile = user.user_profile
    return false unless profile&.onboarding_completed_at

    true
  end

  def handle_daily_greeting
    profile = user.user_profile
    today = Time.current.to_date

    # Get recent workout history
    yesterday_session = get_workout_session(today - 1.day)
    last_week_same_day = get_workout_session(today - 7.days)

    # Summarize sessions for display
    yesterday_summary = yesterday_session ? summarize_session(yesterday_session) : nil
    last_week_summary = last_week_same_day ? summarize_session(last_week_same_day) : nil

    # Build greeting message
    greeting = build_daily_greeting(
      profile: profile,
      yesterday: yesterday_summary,
      last_week: last_week_summary,
      today: today
    )

    success_response(
      message: greeting,
      intent: "DAILY_GREETING",
      data: {
        yesterday_workout: yesterday_summary,
        last_week_workout: last_week_summary,
        suggestions: []
      }
    )
  end

  def get_workout_session(date)
    user.workout_sessions
        .includes(:workout_sets)
        .where(start_time: date.beginning_of_day..date.end_of_day)
        .order(start_time: :desc)
        .first
  end

  def summarize_session(session)
    return nil unless session

    # Get workout sets for this session
    sets = session.workout_sets.order(:created_at)
    exercises_by_name = sets.group_by(&:exercise_name)

    {
      date: session.start_time.to_date.to_s,
      day_korean: session.name || "운동",
      duration_minutes: session.total_duration ? (session.total_duration / 60) : nil,
      exercises: exercises_by_name.map do |name, exercise_sets|
        best = exercise_sets.max_by { |s| (s.weight || 0).to_f }
        {
          name: name,
          sets: exercise_sets.size,
          best_set: best ? { "weight" => best.weight, "reps" => best.reps } : nil
        }
      end,
      total_volume: sets.sum { |s| (s.weight || 0).to_f * (s.reps || 0).to_i }.round(1),
      completed: session.status == "completed"
    }.with_indifferent_access
  end

  def build_daily_greeting(profile:, yesterday:, last_week:, today:)
    name = user.name || "회원"
    day_names = %w[일 월 화 수 목 금 토]
    today_name = day_names[today.wday]

    lines = []
    lines << "#{name}님, 안녕하세요! 💪"
    lines << ""

    # Yesterday's workout summary
    if yesterday
      Rails.logger.info("[DailyGreeting] Yesterday data: #{yesterday.inspect}")
      day_name = yesterday[:day_korean] || yesterday["day_korean"] || "운동"
      duration = yesterday[:duration_minutes] || yesterday["duration_minutes"]
      lines << "📊 **어제 운동 기록**"
      lines << "- #{day_name} (#{duration || '?'}분)"
      exercises = yesterday[:exercises] || []
      exercises.first(3).each do |ex|
        if ex[:best_set]
          lines << "  • #{ex[:name]}: #{ex[:best_set]['weight']}kg x #{ex[:best_set]['reps']}회"
        else
          lines << "  • #{ex[:name]}: #{ex[:sets]}세트"
        end
      end
      if exercises.size > 3
        lines << "  • ... 외 #{exercises.size - 3}개"
      end
      lines << ""
    end

    # Last week same day comparison
    if last_week
      lines << "📅 **지난주 #{today_name}요일**"
      lines << "- #{last_week[:day_korean]} 수행"
      volume = last_week[:total_volume] || 0
      if volume > 0
        lines << "- 총 볼륨: #{volume.to_i}kg"
      end
      lines << ""
    end

    # No recent workout
    if !yesterday && !last_week
      lines << "최근 운동 기록이 없네요. 오늘부터 다시 시작해볼까요? 🔥"
      lines << ""
    end

    # Ask about today's condition
    lines << "---"
    lines << ""
    lines << "오늘 **컨디션**은 어떠세요?"
    lines << ""
    lines << "1️⃣ 컨디션 좋아! → 강도 높여서"
    lines << "2️⃣ 보통이야 → 평소처럼"
    lines << "3️⃣ 좀 피곤해 → 가볍게"

    lines.join("\n")
  end

  # ============================================
  # Today's Routine (Post-Onboarding)
  # ============================================

  def wants_today_routine?
    return false if message.blank?

    # Skip if user still needs level assessment (AI consultation)
    return false if needs_level_assessment?

    # Reload profile to get fresh data (fix stale association)
    profile = UserProfile.find_by(user_id: user.id)
    Rails.logger.info("[wants_today_routine?] user_id=#{user.id}, onboarding_completed_at=#{profile&.onboarding_completed_at}")
    return false unless profile&.onboarding_completed_at.present?

    # Check if no routines exist yet (just finished program creation)
    routine_count = WorkoutRoutine.where(user_id: user.id).count
    Rails.logger.info("[wants_today_routine?] routine_count=#{routine_count}, message=#{message}")

    # If onboarding complete + no routines yet, assume user wants first routine
    routine_count == 0
  end

  def handle_show_today_routine
    # Get user's training program (should exist after onboarding)
    program = user.active_training_program

    # Generate today's routine using the same method as handle_generate_routine
    day_of_week = Time.current.wday
    day_of_week = day_of_week == 0 ? 7 : day_of_week

    result = AiTrainer.generate_routine(
      user: user,
      day_of_week: day_of_week,
      condition_inputs: nil,
      recent_feedbacks: user.workout_feedbacks.order(created_at: :desc).limit(5)
    )

    if result.is_a?(Hash) && result[:success] == false
      return error_response(result[:error] || "루틴 생성에 실패했어요.")
    end

    # Build program info for display
    program_info = if program
      {
        name: program.name,
        current_week: program.current_week,
        total_weeks: program.total_weeks,
        phase: program.current_phase,
        volume_modifier: program.current_volume_modifier
      }
    end

    # Format response with program context
    lines = []
    lines << "오늘의 운동 루틴이에요! 💪"
    lines << ""

    if program_info
      lines << "🗓️ **#{program_info[:name]}** - #{program_info[:current_week]}/#{program_info[:total_weeks]}주차 (#{program_info[:phase]})"
    end

    lines << "📋 **#{result[:day_korean] || '오늘의 운동'}**"
    lines << "⏱️ 예상 시간: #{result[:estimated_duration_minutes] || 45}분"
    lines << ""
    lines << "**운동 목록:**"

    exercises = result[:exercises] || []
    exercises.each_with_index do |ex, idx|
      name = ex[:exercise_name] || ex["exercise_name"] || ex[:name] || ex["name"]
      sets = ex[:sets] || ex["sets"] || 3
      reps = ex[:reps] || ex["reps"] || 10
      lines << "#{idx + 1}. **#{name}** - #{sets}세트 x #{reps}회"
    end

    lines << ""
    lines << "운동을 마치면 **\"운동 끝났어\"** 라고 말씀해주세요!"
    lines << "피드백을 받아 다음 루틴을 최적화해드릴게요 📈"

    success_response(
      message: lines.join("\n"),
      intent: "GENERATE_ROUTINE",
      data: {
        routine: result,
        program: program_info,
        suggestions: ["운동 시작할게", "운동 끝났어"]
      }
    )
  end

  # ============================================
  # Welcome Message (First Chat After Onboarding)
  # ============================================

  def needs_welcome_message?
    return false if message.present? && message != "시작" && message != "start"

    profile = user.user_profile
    return false unless profile&.onboarding_completed_at

    # Welcome if onboarding completed recently AND no workout routines yet
    recently_onboarded = profile.onboarding_completed_at > 5.minutes.ago
    no_routines_yet = !user.workout_routines.exists?

    recently_onboarded && no_routines_yet
  end

  def handle_welcome_message
    profile = user.user_profile
    tier = profile&.tier || "beginner"
    level = profile&.numeric_level || 1
    goal = profile&.fitness_goal || "건강"

    # Get consultation data for personalized plan
    consultation_data = profile&.fitness_factors&.dig("collected_data") || {}

    # Build long-term plan explanation
    long_term_plan = build_long_term_plan(profile, consultation_data)

    prompt = <<~PROMPT
      새로 온보딩을 완료한 사용자에게 장기 운동 계획을 설명하고 첫 루틴을 제안해주세요.

      ## 사용자 정보
      - 이름: #{user.name || '회원'}
      - 레벨: #{level} (#{tier_korean(tier)})
      - 목표: #{goal}
      - 키: #{profile&.height}cm
      - 체중: #{profile&.weight}kg
      - 운동 빈도: #{consultation_data['frequency'] || '주 3회'}
      - 운동 환경: #{consultation_data['environment'] || '헬스장'}
      - 부상/주의사항: #{consultation_data['injuries'] || '없음'}
      - 집중 부위: #{consultation_data['focus_areas'] || '전체'}

      ## 장기 운동 계획
      #{long_term_plan[:description]}

      ## 주간 스플릿
      #{long_term_plan[:weekly_split]}

      ## 응답 규칙
      1. 환영 인사 (이름 포함)
      2. 상담 내용 바탕으로 맞춤 장기 계획 설명 (주간 스플릿, 목표 달성 전략)
      3. "지금 바로 오늘의 루틴을 만들어드릴게요!" 라고 말하며 루틴 생성 예고
      4. 친근하고 격려하는 톤
      5. 4-6문장 정도로 충분히 설명
      6. 이모지 적절히 사용
      7. **마지막에 반드시** "잠시만요, 오늘의 맞춤 루틴을 준비할게요... 💪" 라고 끝내기
    PROMPT

    response = AiTrainer::LlmGateway.chat(
      prompt: prompt,
      task: :welcome_with_plan,
      system: "당신은 친근하면서도 전문적인 피트니스 AI 트레이너입니다. 한국어로 응답하세요."
    )

    welcome_text = if response[:success]
      response[:content]
    else
      default_welcome_with_plan(profile, long_term_plan)
    end

    # Auto-generate first routine
    first_routine = generate_first_routine

    if first_routine && first_routine[:exercises].present?
      # Combine welcome message with routine
      routine_message = format_first_routine_message(first_routine)
      full_message = "#{welcome_text}\n\n---\n\n#{routine_message}"

      success_response(
        message: full_message,
        intent: "WELCOME_WITH_ROUTINE",
        data: {
          is_first_chat: true,
          user_profile: {
            level: level,
            tier: tier,
            goal: goal
          },
          long_term_plan: long_term_plan,
          routine: first_routine,
          suggestions: []
        }
      )
    else
      # Fallback: just welcome message with suggestion
      success_response(
        message: welcome_text,
        intent: "WELCOME",
        data: {
          is_first_chat: true,
          user_profile: {
            level: level,
            tier: tier,
            goal: goal
          },
          long_term_plan: long_term_plan,
          suggestions: []
        }
      )
    end
  end

  def generate_first_routine
    day_of_week = Time.current.wday
    day_of_week = day_of_week == 0 ? 7 : day_of_week
    day_of_week = [day_of_week, 5].min  # Cap at Friday for first routine

    AiTrainer.generate_routine(
      user: user,
      day_of_week: day_of_week,
      condition_inputs: { energy_level: 4, notes: "첫 운동 - 적응 기간" },  # Slightly easier for first workout
      goal: user.user_profile&.fitness_goal
    )
  rescue StandardError => e
    Rails.logger.error("[ChatService] Failed to generate first routine: #{e.message}")
    nil
  end

  def default_welcome_with_plan(profile, long_term_plan)
    name = user.name || "회원"
    goal = profile&.fitness_goal || "건강"
    tier = profile&.tier || "beginner"

    tier_name = tier_korean(tier)
    weekly_split = long_term_plan[:weekly_split]

    "#{name}님, 환영합니다! 🎉\n\n" \
    "상담 내용을 바탕으로 #{name}님만의 운동 계획을 세웠어요.\n\n" \
    "📌 **목표:** #{goal}\n" \
    "📌 **레벨:** #{tier_name}\n" \
    "📌 **주간 스케줄:** #{weekly_split}\n\n" \
    "#{long_term_plan[:description]}\n\n" \
    "잠시만요, 오늘의 맞춤 루틴을 준비할게요... 💪"
  end

  def default_welcome_message(profile)
    name = user.name || "회원"
    goal = profile&.fitness_goal || "건강"

    "#{name}님, 환영합니다! 🎉\n\n" \
    "#{goal} 목표로 함께 운동해봐요. " \
    "\"오늘 루틴 만들어줘\"라고 말씀해주시면 맞춤 운동을 준비해드릴게요! 💪"
  end

  # ============================================
  # Level Assessment (Special Flow)
  # ============================================

  def needs_level_assessment?
    AiTrainer::LevelAssessmentService.needs_assessment?(user)
  end

  def handle_level_assessment
    result = AiTrainer::LevelAssessmentService.assess(user: user, message: message)

    if result[:success]
      # Use TRAINING_PROGRAM intent when program is created (is_complete)
      intent = result[:is_complete] ? "TRAINING_PROGRAM" : "CONSULTATION"

      # Use explicit suggestions from assessment, or extract from message
      suggestions = result[:suggestions].presence || extract_suggestions_from_message(result[:message])

      Rails.logger.info("[handle_level_assessment] intent=#{intent}, suggestions_from_result=#{result[:suggestions].inspect}, final_suggestions=#{suggestions.inspect}")

      # Strip raw "suggestions: [...]" text from message so it doesn't show in chat
      clean_message = strip_suggestions_text(result[:message])

      success_response(
        message: clean_message,
        intent: intent,
        data: {
          is_complete: result[:is_complete],
          assessment: result[:assessment],
          suggestions: suggestions
        }
      )
    else
      error_response(result[:error] || "수준 파악에 실패했어요.")
    end
  end
end
