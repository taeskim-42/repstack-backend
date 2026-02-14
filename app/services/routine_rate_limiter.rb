# frozen_string_literal: true

# Rate limiter for routine generation to control API costs
# Supports 3-tier limits: free (weekly), pro (daily), max (daily)
class RoutineRateLimiter
  # Free tier: weekly limits (주간 제한)
  FREE_LIMITS = {
    routine_generation: { limit: 3, period: :weekly },
    exercise_replacement: { limit: 2, period: :daily },
    routine_regeneration: { limit: 1, period: :weekly }
  }.freeze

  # Pro tier: daily limits
  PRO_LIMITS = {
    routine_generation: { limit: 3, period: :daily },
    exercise_replacement: { limit: 10, period: :daily },
    routine_regeneration: { limit: 3, period: :daily }
  }.freeze

  # Max tier: daily limits (generous)
  MAX_LIMITS = {
    routine_generation: { limit: 10, period: :daily },
    exercise_replacement: { limit: 30, period: :daily },
    routine_regeneration: { limit: 10, period: :daily }
  }.freeze

  TIER_LIMITS = { free: FREE_LIMITS, pro: PRO_LIMITS, max: MAX_LIMITS }.freeze

  CACHE_KEY_PREFIX = "rate_limit:routine"

  class << self
    def allowed?(user:, action:)
      count = current_count(user: user, action: action)
      limit = limit_for(user: user, action: action)

      count < limit
    end

    def increment!(user:, action:)
      key = cache_key(user: user, action: action)
      count = Rails.cache.read(key) || 0
      new_count = count + 1

      Rails.cache.write(key, new_count, expires_in: cache_expiry(user: user, action: action))

      new_count
    end

    def current_count(user:, action:)
      key = cache_key(user: user, action: action)
      Rails.cache.read(key) || 0
    end

    def remaining(user:, action:)
      limit = limit_for(user: user, action: action)
      count = current_count(user: user, action: action)
      [limit - count, 0].max
    end

    def status(user:)
      limits = limits_for_tier(user.subscription_tier)

      limits.to_h do |action, config|
        count = current_count(user: user, action: action)
        [
          action,
          {
            limit: config[:limit],
            period: config[:period],
            used: count,
            remaining: [config[:limit] - count, 0].max
          }
        ]
      end
    end

    def check_and_increment!(user:, action:)
      unless allowed?(user: user, action: action)
        limit_config = limit_config_for(user: user, action: action)
        period_text = limit_config[:period] == :weekly ? "주간" : "일일"
        upgrade_message = upgrade_hint(user)
        return {
          allowed: false,
          error: "#{period_text} #{action_name(action)} 한도(#{limit_config[:limit]}회)를 초과했습니다.#{upgrade_message}",
          remaining: 0,
          upgrade_tier: next_tier(user.subscription_tier)
        }
      end

      new_count = increment!(user: user, action: action)
      limit = limit_for(user: user, action: action)

      {
        allowed: true,
        error: nil,
        remaining: limit - new_count,
        upgrade_tier: nil
      }
    end

    private

    def cache_key(user:, action:)
      config = limit_config_for(user: user, action: action)
      date_key = config[:period] == :weekly ? Date.current.beginning_of_week.to_s : Date.current.to_s
      "#{CACHE_KEY_PREFIX}:#{user.id}:#{action}:#{date_key}"
    end

    def cache_expiry(user:, action:)
      config = limit_config_for(user: user, action: action)
      if config[:period] == :weekly
        time_until_end_of_week
      else
        time_until_midnight
      end
    end

    def time_until_midnight
      now = Time.current
      (now.end_of_day - now).seconds
    end

    def time_until_end_of_week
      now = Time.current
      (now.end_of_week - now).seconds
    end

    def limits_for_tier(tier)
      TIER_LIMITS[tier] || FREE_LIMITS
    end

    def limit_config_for(user:, action:)
      limits = limits_for_tier(user.subscription_tier)
      limits[action.to_sym] || { limit: 1, period: :daily }
    end

    def limit_for(user:, action:)
      limit_config_for(user: user, action: action)[:limit]
    end

    def action_name(action)
      {
        routine_generation: "루틴 생성",
        exercise_replacement: "운동 교체",
        routine_regeneration: "루틴 재생성"
      }[action.to_sym] || action.to_s
    end

    def upgrade_hint(user)
      case user.subscription_tier
      when :free
        " Pro로 업그레이드하면 매일 루틴을 받을 수 있어요!"
      when :pro
        " Max로 업그레이드하면 더 많이 사용할 수 있어요!"
      else
        ""
      end
    end

    def next_tier(current_tier)
      case current_tier
      when :free then :pro
      when :pro then :max
      end
    end
  end
end
