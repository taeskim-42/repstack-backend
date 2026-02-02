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
        model: "claude-haiku-4-5-20251001",
        max_tokens: 512,
        temperature: 0.7
      },
      condition_check: {
        provider: :anthropic,
        model: "claude-haiku-4-5-20251001",
        max_tokens: 1024,
        temperature: 0.3
      },
      feedback_analysis: {
        provider: :anthropic,
        model: "claude-haiku-4-5-20251001",
        max_tokens: 1024,
        temperature: 0.3
      },
      level_assessment: {
        provider: :anthropic,
        model: "claude-haiku-4-5-20251001",
        max_tokens: 1024,
        temperature: 0.5
      },

      # Intent classification - fast, low cost
      intent_classification: {
        provider: :anthropic,
        model: "claude-haiku-4-5-20251001",
        max_tokens: 100,
        temperature: 0.0
      },

      # Query translation for semantic search
      query_translation: {
        provider: :anthropic,
        model: "claude-haiku-4-5-20251001",
        max_tokens: 100,
        temperature: 0.0
      },

      # Knowledge cleanup - needs better reasoning
      knowledge_cleanup: {
        provider: :anthropic,
        model: "claude-haiku-4-5-20251001",
        max_tokens: 200,
        temperature: 0.0
      },

      # YouTube transcript knowledge extraction
      knowledge_extraction: {
        provider: :anthropic,
        model: "claude-haiku-4-5-20251001",
        max_tokens: 16384,  # Increased for long transcripts with many chunks
        temperature: 0.3
      },

      # Exercise replacement suggestion
      exercise_replacement: {
        provider: :anthropic,
        model: "claude-haiku-4-5-20251001",
        max_tokens: 512,
        temperature: 0.5
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
      # @param messages [Array] Optional message history for multi-turn (supports cache_control)
      # @param system [String] Optional system prompt
      # @param cache_system [Boolean] Whether to cache the system prompt (default: true)
      # @param tools [Array] Optional tools for function calling
      # @return [Hash] Response with :success, :content, :model, :usage, :tool_use (if tool called)
      def chat(prompt:, task: :general_chat, messages: nil, system: nil, cache_system: true, tools: nil)
        config = MODELS[task] || MODELS[:general_chat]
        provider_config = PROVIDERS[config[:provider]]

        unless api_configured?(provider_config[:env_key])
          return mock_response(task, tools: tools)
        end

        send("call_#{config[:provider]}", prompt: prompt, config: config, messages: messages, system: system, cache_system: cache_system, tools: tools)
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
      def call_anthropic(prompt:, config:, messages: nil, system: nil, cache_system: true, tools: nil)
        provider = PROVIDERS[:anthropic]
        uri = URI(provider[:api_url])

        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = true
        http.read_timeout = timeout_for_model(config[:model])
        # Fix for Ruby 3.4 OpenSSL CRL verification issue
        http.verify_mode = OpenSSL::SSL::VERIFY_PEER
        http.verify_callback = ->(_preverify_ok, _store_ctx) { true }

        request = Net::HTTP::Post.new(uri.path)
        request["Content-Type"] = "application/json"
        request["x-api-key"] = ENV[provider[:env_key]]
        request["anthropic-version"] = provider[:api_version]
        # Enable prompt caching beta
        request["anthropic-beta"] = "prompt-caching-2024-07-31"

        body = build_anthropic_body(prompt: prompt, config: config, messages: messages, system: system, cache_system: cache_system, tools: tools)
        request.body = body.to_json

        response = http.request(request)
        parse_anthropic_response(response, config[:model])
      end

      def build_anthropic_body(prompt:, config:, messages:, system:, cache_system: true, tools: nil)
        body = {
          model: config[:model],
          max_tokens: config[:max_tokens]
        }

        # Add temperature if specified
        body[:temperature] = config[:temperature] if config[:temperature]

        # Add system prompt with optional caching
        system_prompt = system.presence || config[:system]
        if system_prompt.present?
          if cache_system
            # Use array format for system with cache_control
            body[:system] = [
              {
                type: "text",
                text: system_prompt,
                cache_control: { type: "ephemeral" }
              }
            ]
          else
            body[:system] = system_prompt
          end
        end

        # Build messages array (cache_control must be inside content block)
        if messages.present?
          body[:messages] = messages.map do |msg|
            role = msg[:role] || msg["role"]
            content = msg[:content] || msg["content"]

            # Just pass through - content may already be in array format with cache_control
            { role: role, content: content }
          end
          # Add new user message if prompt is different from last
          if prompt.present? && (messages.empty? || (messages.last[:content] || messages.last["content"]) != prompt)
            body[:messages] << { role: "user", content: prompt }
          end
        else
          body[:messages] = [{ role: "user", content: prompt }]
        end

        # Add tools for function calling
        if tools.present?
          body[:tools] = tools
        end

        body
      end

      def parse_anthropic_response(response, model)
        if response.code.to_i == 200
          data = JSON.parse(response.body)
          usage = data["usage"] || {}
          content_blocks = data["content"] || []

          # Check for tool use
          tool_use_block = content_blocks.find { |block| block["type"] == "tool_use" }
          text_block = content_blocks.find { |block| block["type"] == "text" }

          result = {
            success: true,
            content: text_block&.dig("text"),
            model: model,
            stop_reason: data["stop_reason"],
            usage: {
              input_tokens: usage["input_tokens"],
              output_tokens: usage["output_tokens"],
              cache_creation_input_tokens: usage["cache_creation_input_tokens"],
              cache_read_input_tokens: usage["cache_read_input_tokens"]
            }
          }

          # Add tool use info if present
          if tool_use_block
            result[:tool_use] = {
              id: tool_use_block["id"],
              name: tool_use_block["name"],
              input: tool_use_block["input"]
            }
          end

          result
        else
          Rails.logger.error("[LlmGateway] Anthropic API error: #{response.code} - #{response.body}")
          { success: false, error: "API returned #{response.code}" }
        end
      end

      def timeout_for_model(model)
        case model
        when /sonnet/i then 120
        when /opus/i then 180
        else 180  # Increased for knowledge_extraction with long transcripts
        end
      end

      # Mock response for development without API key
      def mock_response(task, tools: nil)
        Rails.logger.info("[LlmGateway] Mock response for #{task} (API not configured)")

        # If tools are provided, mock a tool use response
        if tools.present?
          return {
            success: true,
            content: "테스트 응답입니다.",
            model: "mock",
            stop_reason: "end_turn",
            usage: { input_tokens: 0, output_tokens: 0 }
          }
        end

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
          stop_reason: "end_turn",
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
        # Return JSON format so parse_response can handle it properly
        {
          message: "좋아요! 운동 경험이 어느 정도 되시나요?",
          next_state: "asking_experience",
          collected_data: {},
          is_complete: false,
          assessment: nil
        }.to_json
      end
    end
  end
end
