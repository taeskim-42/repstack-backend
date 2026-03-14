# frozen_string_literal: true

module ChatOnboarding
  module GreetingBuilder
    private

    def needs_daily_greeting?
      return false unless message.blank? || message == "시작" || message == "start"

      profile = user.user_profile
      return false unless profile&.onboarding_completed_at

      true
    end

    def handle_daily_greeting
      profile = user.user_profile
      today = Time.current.to_date

      yesterday_session = get_workout_session(today - 1.day)
      last_week_same_day = get_workout_session(today - 7.days)

      yesterday_summary = yesterday_session ? summarize_session(yesterday_session) : nil
      last_week_summary = last_week_same_day ? summarize_session(last_week_same_day) : nil

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
        lines << "  • ... 외 #{exercises.size - 3}개" if exercises.size > 3
        lines << ""
      end

      if last_week
        lines << "📅 **지난주 #{today_name}요일**"
        lines << "- #{last_week[:day_korean]} 수행"
        volume = last_week[:total_volume] || 0
        lines << "- 총 볼륨: #{volume.to_i}kg" if volume > 0
        lines << ""
      end

      unless yesterday || last_week
        lines << "최근 운동 기록이 없네요. 오늘부터 다시 시작해볼까요? 🔥"
        lines << ""
      end

      lines << "---"
      lines << ""
      lines << "오늘 **컨디션**은 어떠세요?"
      lines << ""
      lines << "1️⃣ 컨디션 좋아! → 강도 높여서"
      lines << "2️⃣ 보통이야 → 평소처럼"
      lines << "3️⃣ 좀 피곤해 → 가볍게"

      lines.join("\n")
    end
  end
end
