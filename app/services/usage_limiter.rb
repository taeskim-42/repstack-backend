# frozen_string_literal: true

# Comprehensive usage limiter for non-routine features (chat, agent, history, etc.)
# Works alongside RoutineRateLimiter which handles routine-specific limits
class UsageLimiter
  TIER_LIMITS = {
    free: {
      ai_chat: { limit: 5, period: :daily },
      agent_session: { limit: 0, period: :daily }  # Sonnet not available for free
    },
    pro: {
      ai_chat: { limit: 30, period: :daily },
      agent_session: { limit: 5, period: :daily }
    },
    max: {
      ai_chat: { limit: 100, period: :daily },
      agent_session: { limit: 20, period: :daily }
    }
  }.freeze

  # Feature access by tier (non-metered)
  FEATURE_ACCESS = {
    program_periodization: { free: :basic, pro: :custom, max: :custom_ai },
    history_access: { free: :recent_2_weeks, pro: :full, max: :full_dashboard },
    feedback_analysis: { free: :none, pro: :detailed, max: :deep_trend },
    rag_search: { free: false, pro: true, max: true },
    nutrition_analysis: { free: false, pro: false, max: true }
  }.freeze

  CACHE_KEY_PREFIX = "rate_limit:usage"

  class << self
    # Check if a metered action is allowed
    def allowed?(user:, action:)
      limit = limit_for(user: user, action: action)
      return false if limit == 0

      count = current_count(user: user, action: action)
      count < limit
    end

    def increment!(user:, action:)
      key = cache_key(user: user, action: action)
      count = Rails.cache.read(key) || 0
      new_count = count + 1

      Rails.cache.write(key, new_count, expires_in: time_until_midnight)
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

    def check_and_increment!(user:, action:)
      limit = limit_for(user: user, action: action)

      if limit == 0
        return {
          allowed: false,
          error: feature_unavailable_message(action, user.subscription_tier),
          remaining: 0,
          upgrade_tier: next_tier(user.subscription_tier)
        }
      end

      unless allowed?(user: user, action: action)
        return {
          allowed: false,
          error: limit_exceeded_message(action, limit, user),
          remaining: 0,
          upgrade_tier: next_tier(user.subscription_tier)
        }
      end

      new_count = increment!(user: user, action: action)

      {
        allowed: true,
        error: nil,
        remaining: limit - new_count,
        upgrade_tier: nil
      }
    end

    # Check non-metered feature access
    def feature_available?(user:, feature:)
      tier = user.subscription_tier
      access = FEATURE_ACCESS.dig(feature.to_sym, tier)
      access.present? && access != false && access != :none
    end

    def feature_level(user:, feature:)
      tier = user.subscription_tier
      FEATURE_ACCESS.dig(feature.to_sym, tier)
    end

    # Full status for a user (all metered limits)
    def status(user:)
      tier = user.subscription_tier
      limits = TIER_LIMITS[tier] || TIER_LIMITS[:free]

      metered = limits.to_h do |action, config|
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

      features = FEATURE_ACCESS.to_h do |feature, tiers|
        [feature, tiers[tier]]
      end

      { metered: metered, features: features }
    end

    # History cutoff date based on tier
    def history_cutoff(user:)
      case user.subscription_tier
      when :free
        2.weeks.ago
      else
        nil  # No cutoff for pro/max
      end
    end

    private

    def cache_key(user:, action:)
      date = Date.current.to_s
      "#{CACHE_KEY_PREFIX}:#{user.id}:#{action}:#{date}"
    end

    def time_until_midnight
      now = Time.current
      (now.end_of_day - now).seconds
    end

    def limit_for(user:, action:)
      tier = user.subscription_tier
      limits = TIER_LIMITS[tier] || TIER_LIMITS[:free]
      config = limits[action.to_sym]
      config ? config[:limit] : 0
    end

    def action_name(action)
      {
        ai_chat: "AI 채팅",
        agent_session: "AI 트레이너 상담"
      }[action.to_sym] || action.to_s
    end

    def feature_unavailable_message(action, tier)
      case action.to_sym
      when :agent_session
        if tier == :free
          "AI 트레이너의 심층 분석은 Pro 전용 기능이에요. 업그레이드하면 매일 5회까지 사용할 수 있어요!"
        else
          "#{action_name(action)}은 상위 플랜에서 사용할 수 있어요."
        end
      else
        "이 기능은 구독 업그레이드가 필요합니다."
      end
    end

    def limit_exceeded_message(action, limit, user)
      upgrade = upgrade_hint(user)
      "일일 #{action_name(action)} 한도(#{limit}회)를 초과했습니다.#{upgrade}"
    end

    def upgrade_hint(user)
      case user.subscription_tier
      when :free
        " Pro로 업그레이드하면 더 많이 사용할 수 있어요!"
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
