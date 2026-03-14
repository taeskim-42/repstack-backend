# frozen_string_literal: true

require_relative "constants"
require_relative "llm_gateway"
require_relative "program_generator"
require_relative "level_assessment/assessment_constants"
require_relative "level_assessment/prompt_builder"
require_relative "level_assessment/response_parser"
require_relative "level_assessment/profile_manager"
require_relative "level_assessment/analytics_tracker"

module AiTrainer
  # Handles initial user level assessment through conversational AI
  # Routes to cost-efficient models via LLM Gateway
  # Automatically triggered for new users without level_assessed_at
  class LevelAssessmentService
    include Constants
    include LevelAssessment::AssessmentConstants
    include LevelAssessment::PromptBuilder
    include LevelAssessment::ResponseParser
    include LevelAssessment::ProfileManager
    include LevelAssessment::AnalyticsTracker

    class << self
      def assess(user:, message:)
        new(user: user).assess(message)
      end

      def needs_assessment?(user)
        profile = user.user_profile
        return false unless profile

        # Need assessment if form onboarding is done but AI consultation is not
        profile.form_onboarding_completed_at.present? && profile.onboarding_completed_at.nil?
      end
    end

    def initialize(user:)
      @user = user
      @profile = user.user_profile || user.create_user_profile!
    end

    def assess(message)
      analytics = get_or_create_analytics
      current_state = get_assessment_state

      # FIRST GREETING: When user enters chat mode after form onboarding
      if current_state == STATES[:initial] && (message.blank? || message == "start" || message == "시작")
        return handle_first_greeting(analytics)
      end

      unless LlmGateway.configured?(task: :level_assessment)
        Rails.logger.info("[LevelAssessmentService] Using mock response (API not configured)")
        result = mock_response(message)
        update_analytics(analytics, message, { message: result[:message], collected_data: get_collected_data })
        return result
      end

      conversation = build_conversation(message, current_state)

      response = LlmGateway.chat(
        prompt: message,
        task: :level_assessment,
        messages: conversation[:messages],
        system: conversation[:system]
      )

      if response[:success]
        result = parse_response(response, message)
      else
        return mock_response
      end

      if result[:is_complete]
        # IMPORTANT: Save collected_data to DB BEFORE generating program
        save_assessment_state(STATES[:completed], result[:collected_data])

        update_profile_with_assessment(result[:assessment])
        complete_analytics(analytics, result[:collected_data], "user_ready")

        program_result = generate_initial_routine(result[:collected_data])
        completion_message = build_completion_message_with_routine(result[:message], program_result)

        return {
          success: true,
          message: completion_message,
          is_complete: true,
          assessment: result[:assessment],
          program: program_result[:program],
          suggestions: result[:suggestions].presence || [ "오늘 루틴 만들어줘", "프로그램 자세히 설명해줘", "나중에 할게" ]
        }
      else
        save_assessment_state(result[:next_state], result[:collected_data])
        update_analytics(analytics, message, result)
      end

      {
        success: true,
        message: result[:message],
        is_complete: result[:is_complete],
        assessment: result[:is_complete] ? result[:assessment] : nil,
        suggestions: result[:suggestions]
      }
    rescue StandardError => e
      Rails.logger.error("LevelAssessmentService error: #{e.message}")
      Rails.logger.error(e.backtrace.first(5).join("\n"))
      record_analytics_error(analytics, e.message) if analytics
      { success: false, message: "수준 파악 중 오류가 발생했습니다.", error: e.message }
    end

    private

    attr_reader :user, :profile

    VOICE_HINT = "\n\n💡 하단의 🎤 버튼을 누르면 음성으로 편하게 대화할 수 있어요!"

    def handle_first_greeting(analytics)
      form_data = extract_form_data
      next_state = determine_next_state(form_data)
      save_assessment_state(next_state, form_data)

      if LlmGateway.configured?(task: :level_assessment)
        greeting_instruction = "사용자가 처음 채팅에 들어왔습니다. 이미 파악된 정보를 확인했다고 언급하고, 첫 번째 질문을 해주세요."
        conversation = build_conversation(greeting_instruction, next_state)

        response = LlmGateway.chat(
          prompt: greeting_instruction,
          task: :level_assessment,
          messages: conversation[:messages],
          system: conversation[:system]
        )

        if response[:success]
          result = parse_response(response, "")
          update_analytics(analytics, "", { message: result[:message], collected_data: form_data })
          return {
            success: true,
            message: result[:message] + VOICE_HINT,
            is_complete: false,
            assessment: nil,
            suggestions: result[:suggestions]
          }
        end
      end

      # Fallback: hardcoded greeting (only if LLM fails or not configured)
      greeting = build_personalized_greeting(form_data)
      update_analytics(analytics, "", { message: greeting, collected_data: form_data })

      {
        success: true,
        message: greeting + VOICE_HINT,
        is_complete: false,
        assessment: nil,
        suggestions: []
      }
    end

    def mock_response(message = nil)
      collected = get_collected_data
      if user_wants_routine?(message.to_s)
        complete_assessment(collected)
      else
        {
          success: true,
          message: "네, 알겠습니다! 운동 빈도는 어떻게 되세요?",
          is_complete: false,
          assessment: nil,
          suggestions: [ "주 3회", "주 4-5회", "매일" ]
        }
      end
    end
  end
end
