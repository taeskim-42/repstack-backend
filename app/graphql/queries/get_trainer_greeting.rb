# frozen_string_literal: true

module Queries
  class GetTrainerGreeting < BaseQuery
    description "Get AI trainer greeting message for returning users (day 2+)"

    type Types::TrainerGreetingType, null: false

    def resolve
      authenticate_user!

      @locale = context[:locale] || "ko"

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
        error: I18n.t("greeting.onboarding_required", locale: @locale)
      }
    end

    def first_day_response(profile)
      user_name = current_user.name || I18n.t("greeting.default_name", locale: @locale)
      day_info = today_info

      {
        success: true,
        message: I18n.t(
          "greeting.first_day",
          locale: @locale,
          name: user_name,
          day: day_info[:localized_day],
          factor: day_info[:localized_factor]
        ),
        intent: "GENERATE_ROUTINE",
        data: nil,
        error: nil
      }
    end

    def already_checked_response(_profile)
      user_name = current_user.name || I18n.t("greeting.default_name", locale: @locale)

      {
        success: true,
        message: I18n.t("greeting.already_checked", locale: @locale, name: user_name),
        intent: "GENERATE_ROUTINE",
        data: nil,
        error: nil
      }
    end

    def greeting_response(profile)
      user_name = current_user.name || I18n.t("greeting.default_name", locale: @locale)
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
      greeting = time_based_greeting
      level_info = level_context(profile)

      I18n.t(
        "greeting.daily_greeting",
        locale: @locale,
        greeting: greeting,
        name: user_name,
        day: day_info[:localized_day],
        factor: day_info[:localized_factor],
        level_info: level_info
      )
    end

    def time_based_greeting
      hour = Time.current.hour
      key = case hour
      when 5..11 then "morning"
      when 12..17 then "afternoon"
      when 18..21 then "evening"
      else "default"
      end
      I18n.t("greeting.#{key}", locale: @locale)
    end

    def level_context(profile)
      level = profile.numeric_level || 1
      week = profile.week_number || 1

      tier = AiTrainer::Constants.tier_for_level(level)
      tier_name = Localizable.translate(:tiers, tier, @locale)

      I18n.t("greeting.level_context", locale: @locale, tier: tier_name, week: week)
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
        localized_day: Localizable.translate(:days, day_of_week, @locale),
        fitness_factor: fitness_factor,
        fitness_factor_korean: fitness_factor_info[:korean],
        localized_factor: Localizable.translate(:fitness_factors, fitness_factor.to_s, @locale)
      }
    end
  end
end
