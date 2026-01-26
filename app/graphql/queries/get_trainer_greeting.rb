# frozen_string_literal: true

module Queries
  class GetTrainerGreeting < BaseQuery
    description "Get AI trainer greeting message for returning users (day 2+)"

    type Types::TrainerGreetingType, null: false

    def resolve
      authenticate_user!

      profile = current_user.user_profile

      # New user without profile - should go through onboarding
      unless profile&.onboarding_completed_at
        return not_ready_response
      end

      # Day 1 user - should complete first workout before greeting
      if first_day_user?(profile)
        return first_day_response(profile)
      end

      # Already checked condition today
      if already_checked_condition_today?
        return already_checked_response(profile)
      end

      # Normal greeting with condition question
      greeting_response(profile)
    end

    private

    def first_day_user?(profile)
      return true unless profile.onboarding_completed_at

      days_since_onboarding = (Date.current - profile.onboarding_completed_at.to_date).to_i
      days_since_onboarding < 1
    end

    def already_checked_condition_today?
      current_user.condition_logs.exists?(date: Date.current)
    end

    def not_ready_response
      {
        success: false,
        message: nil,
        intent: nil,
        data: nil,
        error: "온보딩을 먼저 완료해주세요."
      }
    end

    def first_day_response(profile)
      user_name = current_user.name || "회원"
      day_info = today_info

      {
        success: true,
        message: "안녕하세요, #{user_name}님! 오늘은 #{day_info[:korean]}이에요. " \
                 "첫 운동을 시작해볼까요? 오늘의 체력 요인은 #{day_info[:fitness_factor_korean]}입니다. 💪",
        intent: "GENERATE_ROUTINE",
        data: nil,
        error: nil
      }
    end

    def already_checked_response(_profile)
      user_name = current_user.name || "회원"

      {
        success: true,
        message: "#{user_name}님, 오늘 컨디션 체크는 완료했어요! 루틴을 시작할까요? 💪",
        intent: "GENERATE_ROUTINE",
        data: nil,
        error: nil
      }
    end

    def greeting_response(profile)
      user_name = current_user.name || "회원"
      day_info = today_info

      message = build_greeting_message(user_name, day_info, profile)

      {
        success: true,
        message: message,
        intent: "CHECK_CONDITION",
        data: {
          current_level: profile.numeric_level
        },
        error: nil
      }
    end

    def build_greeting_message(user_name, day_info, profile)
      greetings = time_based_greeting
      level_info = level_context(profile)

      "#{greetings} #{user_name}님! 오늘은 #{day_info[:korean]}이에요. " \
      "오늘의 체력 요인은 #{day_info[:fitness_factor_korean]}입니다. " \
      "#{level_info}오늘 컨디션은 어떠세요?"
    end

    def time_based_greeting
      hour = Time.current.hour
      case hour
      when 5..11 then "좋은 아침이에요,"
      when 12..17 then "안녕하세요,"
      when 18..21 then "좋은 저녁이에요,"
      else "안녕하세요,"
      end
    end

    def level_context(profile)
      level = profile.numeric_level || 1
      week = profile.week_number || 1

      tier = AiTrainer::Constants.tier_for_level(level)
      tier_korean = case tier
                    when "beginner" then "초급"
                    when "intermediate" then "중급"
                    when "advanced" then "고급"
                    else "초급"
                    end

      "현재 #{tier_korean} #{week}주차 진행 중이시네요. "
    end

    def today_info
      day_of_week = Date.current.cwday # 1=Monday, 7=Sunday
      day_of_week = 1 if day_of_week > 5 # Weekend -> Monday's factor

      weekly_structure = AiTrainer::Constants::WEEKLY_STRUCTURE[day_of_week]
      fitness_factor = weekly_structure[:fitness_factor]
      fitness_factor_info = AiTrainer::Constants::FITNESS_FACTORS[fitness_factor]

      {
        day_number: day_of_week,
        korean: weekly_structure[:korean],
        fitness_factor: fitness_factor,
        fitness_factor_korean: fitness_factor_info[:korean]
      }
    end
  end
end
