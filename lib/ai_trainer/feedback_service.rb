# frozen_string_literal: true

require_relative "constants"
require_relative "llm_gateway"
require_relative "feedback/prompt_templates"
require_relative "feedback/response_parser"

module AiTrainer
  # Analyzes workout feedback from natural language text
  # Routes to cost-efficient models via LLM Gateway
  # Stores feedback for future routine personalization
  class FeedbackService
    include Constants
    include Feedback::PromptTemplates
    include Feedback::ResponseParser

    class << self
      # For ChatService - returns chat-friendly response
      def analyze_from_text(user:, text:, routine_id: nil)
        new(user: user).analyze_from_text(text, routine_id: routine_id)
      end

      # For SubmitFeedback mutation - structured input
      def analyze_from_input(user:, input:)
        new(user: user).analyze_from_input(input)
      end

      # For SubmitFeedbackFromVoice mutation - voice input with feedback parsing
      def analyze_from_voice(user:, text:, routine_id: nil)
        new(user: user).analyze_from_voice(text, routine_id: routine_id)
      end
    end

    def initialize(user:)
      @user = user
    end

    def analyze_from_text(text, routine_id: nil)
      prompt = build_prompt(text)
      response = LlmGateway.chat(prompt: prompt, task: :feedback_analysis)

      if response[:success]
        parse_and_save_response(response[:content], text, routine_id)
      else
        mock_response
      end
    rescue StandardError => e
      Rails.logger.error("FeedbackService error: #{e.message}")
      { success: false, error: "피드백 분석 실패: #{e.message}" }
    end

    # For SubmitFeedback mutation - structured input returns analysis
    def analyze_from_input(input)
      prompt = build_input_prompt(input)
      response = LlmGateway.chat(prompt: prompt, task: :feedback_analysis)

      if response[:success]
        parse_input_response(response[:content])
      else
        mock_input_response(input)
      end
    rescue StandardError => e
      Rails.logger.error("FeedbackService.analyze_from_input error: #{e.message}")
      { success: false, error: "피드백 분석 실패: #{e.message}" }
    end

    # For SubmitFeedbackFromVoice mutation - voice input returns feedback + analysis
    def analyze_from_voice(text, routine_id: nil)
      prompt = build_voice_prompt(text, routine_id)
      response = LlmGateway.chat(prompt: prompt, task: :feedback_analysis)

      if response[:success]
        parse_voice_response(response[:content])
      else
        mock_voice_response(text)
      end
    rescue StandardError => e
      Rails.logger.error("FeedbackService.analyze_from_voice error: #{e.message}")
      { success: false, error: "음성 피드백 분석 실패: #{e.message}" }
    end

    private

    attr_reader :user

    def extract_json(text)
      if text =~ /```(?:json)?\s*(\{.*?\})\s*```/m
        Regexp.last_match(1)
      elsif text.include?("{")
        start_idx = text.index("{")
        end_idx = text.rindex("}")
        text[start_idx..end_idx] if start_idx && end_idx
      else
        text
      end
    end

    def save_feedback(data, original_text, routine_id)
      user.workout_feedbacks.create!(
        feedback: original_text,
        feedback_type: data["feedback_type"] || "general",
        rating: data["rating"] || 3,
        suggestions: data["adaptations"] || [],
        routine_id: routine_id,
        would_recommend: (data["rating"] || 3) >= 3
      )
    rescue ActiveRecord::RecordInvalid => e
      Rails.logger.warn("FeedbackService: Failed to save feedback: #{e.message}")
    end
  end
end
