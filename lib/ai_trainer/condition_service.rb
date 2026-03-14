# frozen_string_literal: true

require_relative "constants"
require_relative "llm_gateway"
require_relative "condition/prompt_templates"
require_relative "condition/response_parser"

module AiTrainer
  # Analyzes user condition from natural language text
  # Routes to cost-efficient models via LLM Gateway
  class ConditionService
    include Constants
    include Condition::PromptTemplates
    include Condition::ResponseParser

    class << self
      # For ChatService - returns chat-friendly response
      def analyze_from_text(user:, text:)
        new(user: user).analyze_from_text(text)
      end

      # For CheckCondition mutation - structured input
      def analyze_from_input(user:, input:)
        new(user: user).analyze_from_input(input)
      end

      # For CheckConditionFromVoice mutation - voice input with condition parsing
      def analyze_from_voice(user:, text:)
        new(user: user).analyze_from_voice(text)
      end
    end

    def initialize(user:)
      @user = user
    end

    def analyze_from_text(text)
      prompt = build_prompt(text)
      response = LlmGateway.chat(prompt: prompt, task: :condition_check)

      if response[:success]
        parse_response(response[:content], text)
      else
        mock_response
      end
    rescue StandardError => e
      Rails.logger.error("ConditionService error: #{e.message}")
      { success: false, error: "컨디션 분석 실패: #{e.message}" }
    end

    # For CheckCondition mutation - structured input returns adaptations
    def analyze_from_input(input)
      prompt = build_input_prompt(input)
      response = LlmGateway.chat(prompt: prompt, task: :condition_check)

      if response[:success]
        parse_input_response(response[:content])
      else
        mock_input_response(input)
      end
    rescue StandardError => e
      Rails.logger.error("ConditionService.analyze_from_input error: #{e.message}")
      { success: false, error: "컨디션 분석 실패: #{e.message}" }
    end

    # For CheckConditionFromVoice mutation - voice input returns condition + adaptations
    def analyze_from_voice(text)
      prompt = build_voice_prompt(text)
      response = LlmGateway.chat(prompt: prompt, task: :condition_check)

      if response[:success]
        parse_voice_response(response[:content])
      else
        mock_voice_response(text)
      end
    rescue StandardError => e
      Rails.logger.error("ConditionService.analyze_from_voice error: #{e.message}")
      { success: false, error: "음성 컨디션 분석 실패: #{e.message}" }
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

    def save_condition_log(parsed_condition)
      return unless parsed_condition

      user.condition_logs.create!(
        date: Date.current,
        energy_level: parsed_condition["energy_level"] || 3,
        stress_level: parsed_condition["stress_level"] || 3,
        sleep_quality: parsed_condition["sleep_quality"] || 3,
        motivation: parsed_condition["motivation"] || 3,
        soreness: {},
        available_time: 60,
        notes: "Chat에서 입력"
      )
    rescue ActiveRecord::RecordInvalid => e
      Rails.logger.warn("ConditionService: Failed to save condition log: #{e.message}")
    end
  end
end
