# frozen_string_literal: true

module AiTrainer
  module LevelAssessment
    # Tracks onboarding analytics — create, update, complete, and record errors.
    # All methods access @user via the host class.
    module AnalyticsTracker
      include AssessmentConstants

      def get_or_create_analytics
        session_id = get_session_id
        OnboardingAnalytics.find_or_create_by!(user: user, session_id: session_id) do |a|
          a.prompt_version = PROMPT_VERSION
          a.conversation_log = []
        end
      rescue ActiveRecord::RecordNotUnique
        OnboardingAnalytics.find_by(session_id: session_id)
      rescue StandardError => e
        Rails.logger.warn("Failed to create analytics: #{e.message}")
        nil
      end

      def update_analytics(analytics, user_message, result)
        return unless analytics

        analytics.turn_count += 1
        analytics.conversation_log << {
          turn: analytics.turn_count,
          user: user_message,
          assistant: result[:message],
          timestamp: Time.current.iso8601
        }
        analytics.collected_info = result[:collected_data] || {}
        analytics.save
      rescue StandardError => e
        Rails.logger.warn("Failed to update analytics: #{e.message}")
      end

      def complete_analytics(analytics, collected_data, reason)
        return unless analytics

        analytics.update(
          completed: true,
          completion_reason: reason,
          collected_info: collected_data || {},
          time_to_complete_seconds: (Time.current - analytics.created_at).to_i
        )
      rescue StandardError => e
        Rails.logger.warn("Failed to complete analytics: #{e.message}")
      end

      def record_analytics_error(analytics, error_message)
        return unless analytics

        analytics.update(
          completion_reason: "error",
          collected_info: (analytics.collected_info || {}).merge("error" => error_message)
        )
      rescue StandardError => e
        Rails.logger.warn("Failed to record analytics error: #{e.message}")
      end

      private

      def get_session_id
        "onboarding-#{user.id}-#{Date.current}"
      end
    end
  end
end
