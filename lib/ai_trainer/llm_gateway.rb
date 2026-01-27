# frozen_string_literal: true

module AiTrainer
  # Unified LLM Gateway for multi-model routing
  # Supports routing different tasks to different models for cost optimization
  #
  # Usage:
  #   LlmGateway.chat(prompt: "...", task: :general_chat)
  #   LlmGateway.chat(prompt: "...", task: :routine_generation)
  #
  class LlmGateway
    # Model configurations by task type
    MODELS = {
      # Expensive model - for complex generation tasks
      routine_generation: {
        provider: :anthropic,
        model: "claude-sonnet-4-20250514",
        max_tokens: 4096,
        temperature: 0.7
      },

      # Cost-efficient - for simple conversational tasks
      general_chat: {
        provider: :anthropic,
        model: "claude-3-5-haiku-latest",
        max_tokens: 512,
        temperature: 0.7
      },
      condition_check: {
        provider: :anthropic,
        model: "claude-3-5-haiku-latest",
        max_tokens: 1024,
        temperature: 0.3,
        system: "당신은 피트니스 트레이너입니다. 사용자가 오늘 컨디션을 말하면 이해하고 운동 강도를 조절하세요. 한국어 슬랭도 자연스럽게 이해하세요."
      },
      feedback_analysis: {
        provider: :anthropic,
        model: "claude-3-5-haiku-latest",
        max_tokens: 1024,
        temperature: 0.3
      },
      level_assessment: {
        provider: :anthropic,
        model: "claude-3-5-haiku-latest",
        max_tokens: 1024,
        temperature: 0.5
      },

      # Intent classification - fast, low cost
      intent_classification: {
        provider: :anthropic,
        model: "claude-3-5-haiku-latest",
        max_tokens: 100,
        temperature: 0.0
      },

      # Knowledge cleanup - needs better reasoning
      knowledge_cleanup: {
        provider: :anthropic,
        model: "claude-3-5-haiku-latest",
        max_tokens: 200,
        temperature: 0.0
      }
    }.freeze

    # Provider API configurations
    PROVIDERS = {
      anthropic: {
        api_url: "https://api.anthropic.com/v1/messages",
        api_version: "2023-06-01",
        env_key: "ANTHROPIC_API_KEY"
      },
      google: {
        api_url: "https://generativelanguage.googleapis.com/v1beta/models",
        env_key: "GOOGLE_API_KEY"
      }
    }.freeze

    class << self
      # Main entry point for LLM calls
      # @param prompt [String] The prompt to send
      # @param task [Symbol] Task type for model routing
      # @param messages [Array] Optional message history for multi-turn
      # @param system [String] Optional system prompt
      # @return [Hash] Response with :success, :content, :model, :usage
      def chat(prompt:, task: :general_chat, messages: nil, system: nil)
        config = MODELS[task] || MODELS[:general_chat]
        provider_config = PROVIDERS[config[:provider]]

        unless api_configured?(provider_config[:env_key])
          return mock_response(task)
        end

        send("call_#{config[:provider]}", prompt: prompt, config: config, messages: messages, system: system)
      rescue StandardError => e
        Rails.logger.error("[LlmGateway] #{task} error: #{e.message}")
        { success: false, error: e.message }
      end

      # Get model info for a task (useful for logging/debugging)
      def model_for(task)
        MODELS[task] || MODELS[:general_chat]
      end

      # Check if the gateway is configured
      def configured?(task: :general_chat)
        config = MODELS[task] || MODELS[:general_chat]
        provider_config = PROVIDERS[config[:provider]]
        api_configured?(provider_config[:env_key])
      end

      private

      def api_configured?(env_key)
        ENV[env_key].present?
      end

      # Anthropic Claude API call
      def call_anthropic(prompt:, config:, messages: nil, system: nil)
        provider = PROVIDERS[:anthropic]
        uri = URI(provider[:api_url])

        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = true
        http.read_timeout = timeout_for_model(config[:model])

        request = Net::HTTP::Post.new(uri.path)
        request["Content-Type"] = "application/json"
        request["x-api-key"] = ENV[provider[:env_key]]
        request["anthropic-version"] = provider[:api_version]

        body = build_anthropic_body(prompt: prompt, config: config, messages: messages, system: system)
        request.body = body.to_json

        response = http.request(request)
        parse_anthropic_response(response, config[:model])
      end

      def build_anthropic_body(prompt:, config:, messages:, system:)
        body = {
          model: config[:model],
          max_tokens: config[:max_tokens]
        }

        # Add temperature if specified
        body[:temperature] = config[:temperature] if config[:temperature]

        # Add system prompt (from param or config)
        system_prompt = system.presence || config[:system]
        body[:system] = system_prompt if system_prompt.present?

        # Build messages array
        if messages.present?
          body[:messages] = messages
          # Add new user message if prompt is different from last
          if prompt.present? && (messages.empty? || messages.last[:content] != prompt)
            body[:messages] << { role: "user", content: prompt }
          end
        else
          body[:messages] = [{ role: "user", content: prompt }]
        end

        body
      end

      def parse_anthropic_response(response, model)
        if response.code.to_i == 200
          data = JSON.parse(response.body)
          {
            success: true,
            content: data.dig("content", 0, "text"),
            model: model,
            usage: {
              input_tokens: data.dig("usage", "input_tokens"),
              output_tokens: data.dig("usage", "output_tokens")
            }
          }
        else
          Rails.logger.error("[LlmGateway] Anthropic API error: #{response.code} - #{response.body}")
          { success: false, error: "API returned #{response.code}" }
        end
      end

      def timeout_for_model(model)
        case model
        when /sonnet/i then 60
        when /opus/i then 90
        else 30
        end
      end

      # Mock response for development without API key
      def mock_response(task)
        Rails.logger.info("[LlmGateway] Mock response for #{task} (API not configured)")

        content = case task
        when :routine_generation
          mock_routine_json
        when :condition_check
          mock_condition_json
        when :feedback_analysis
          mock_feedback_json
        when :level_assessment
          mock_assessment_response
        when :intent_classification
          "general_chat"
        else
          "이것은 테스트 응답입니다. API 키가 설정되면 실제 AI 응답을 받을 수 있어요! 💪"
        end

        {
          success: true,
          content: content,
          model: "mock",
          usage: { input_tokens: 0, output_tokens: 0 }
        }
      end

      def mock_routine_json
        {
          exercises: [
            {
              order: 1,
              exercise_id: "EX_CH01",
              exercise_name: "벤치프레스",
              exercise_name_english: "Bench Press",
              target_muscle: "chest",
              target_muscle_korean: "가슴",
              equipment: "barbell",
              sets: 4,
              reps: 10,
              bpm: 30,
              rest_seconds: 90,
              rest_type: "time_based",
              range_of_motion: "full",
              target_weight_kg: 60,
              weight_description: "목표 중량: 60kg",
              instructions: "가슴을 펴고 바를 천천히 내린 후 폭발적으로 밀어올립니다."
            }
          ],
          estimated_duration_minutes: 45,
          notes: ["오늘은 가슴 중심 운동입니다", "마지막 세트는 힘들어도 포기하지 마세요"],
          variation_seed: "가슴 집중 루틴"
        }.to_json
      end

      def mock_condition_json
        {
          score: 80,
          status: "good",
          message: "컨디션이 좋네요! 오늘 운동하기 딱 좋은 상태입니다.",
          recommendations: ["충분한 수분 섭취를 유지하세요"],
          adaptations: []
        }.to_json
      end

      def mock_feedback_json
        {
          analysis: "운동을 잘 수행하셨네요!",
          suggestions: ["다음에는 무게를 조금 올려보세요"],
          encouragement: "꾸준히 잘하고 계세요! 💪"
        }.to_json
      end

      def mock_assessment_response
        "좋아요! 운동 경험이 어느 정도 되시나요?"
      end
    end
  end
end
