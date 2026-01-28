# frozen_string_literal: true

# Rate limiter for routine generation to control API costs
class RoutineRateLimiter
  # Limits per user per day
  DAILY_LIMITS = {
    routine_generation: 5,      # Full routine generation
    exercise_replacement: 10,   # Single exercise replacement
    routine_regeneration: 3     # Regenerate entire routine
  }.freeze

  CACHE_KEY_PREFIX = "rate_limit:routine"
  CACHE_EXPIRY = 24.hours

  class << self
    # Check if action is allowed
    def allowed?(user:, action:)
      count = current_count(user: user, action: action)
      limit = DAILY_LIMITS[action.to_sym] || 5

      count < limit
    end

    # Increment counter and return new count
    def increment!(user:, action:)
      key = cache_key(user: user, action: action)
      count = Rails.cache.read(key) || 0
      new_count = count + 1

      Rails.cache.write(key, new_count, expires_in: time_until_midnight)

      new_count
    end

    # Get current count
    def current_count(user:, action:)
      key = cache_key(user: user, action: action)
      Rails.cache.read(key) || 0
    end

    # Get remaining quota
    def remaining(user:, action:)
      limit = DAILY_LIMITS[action.to_sym] || 5
      count = current_count(user: user, action: action)
      [limit - count, 0].max
    end

    # Get all limits status for a user
    def status(user:)
      DAILY_LIMITS.transform_values.with_index do |(limit, _), action|
        action_sym = DAILY_LIMITS.keys[action]
        count = current_count(user: user, action: action_sym)
        {
          limit: limit,
          used: count,
          remaining: [limit - count, 0].max
        }
      end

      DAILY_LIMITS.to_h do |action, limit|
        count = current_count(user: user, action: action)
        [
          action,
          {
            limit: limit,
            used: count,
            remaining: [limit - count, 0].max
          }
        ]
      end
    end

    # Check and increment in one call (atomic operation)
    def check_and_increment!(user:, action:)
      unless allowed?(user: user, action: action)
        limit = DAILY_LIMITS[action.to_sym] || 5
        return {
          allowed: false,
          error: "일일 #{action_name(action)} 한도(#{limit}회)를 초과했습니다. 내일 다시 시도해주세요.",
          remaining: 0
        }
      end

      new_count = increment!(user: user, action: action)
      limit = DAILY_LIMITS[action.to_sym] || 5

      {
        allowed: true,
        error: nil,
        remaining: limit - new_count
      }
    end

    private

    def cache_key(user:, action:)
      date = Date.current.to_s
      "#{CACHE_KEY_PREFIX}:#{user.id}:#{action}:#{date}"
    end

    def time_until_midnight
      now = Time.current
      midnight = now.end_of_day
      (midnight - now).seconds
    end

    def action_name(action)
      names = {
        routine_generation: "루틴 생성",
        exercise_replacement: "운동 교체",
        routine_regeneration: "루틴 재생성"
      }
      names[action.to_sym] || action.to_s
    end
  end
end
