# frozen_string_literal: true

require_relative "llm_gateway/model_configs"
require_relative "llm_gateway/mock_factory"

module AiTrainer
  # Unified LLM Gateway for multi-model routing
  # Supports routing different tasks to different models for cost optimization
  #
  # Usage:
  #   LlmGateway.chat(prompt: "...", task: :general_chat)
  #   LlmGateway.chat(prompt: "...", task: :routine_generation)
  #
  class LlmGateway
    include LlmGatewayModelConfigs
    include LlmGatewayMockFactory

    # Delegate constants from the included module so they are accessible
    # as LlmGateway::MODELS and LlmGateway::PROVIDERS
    MODELS    = LlmGatewayModelConfigs::MODELS
    PROVIDERS = LlmGatewayModelConfigs::PROVIDERS

    class << self
      include LlmGatewayMockFactory

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

        body[:temperature] = config[:temperature] if config[:temperature]

        system_prompt = system.presence || config[:system]
        if system_prompt.present?
          if cache_system
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

        if messages.present?
          body[:messages] = messages.map do |msg|
            role = msg[:role] || msg["role"]
            content = msg[:content] || msg["content"]
            { role: role, content: content }
          end
          if prompt.present? && (messages.empty? || (messages.last[:content] || messages.last["content"]) != prompt)
            body[:messages] << { role: "user", content: prompt }
          end
        else
          body[:messages] = [ { role: "user", content: prompt } ]
        end

        body[:tools] = tools if tools.present?

        body
      end

      def parse_anthropic_response(response, model)
        if response.code.to_i == 200
          data = JSON.parse(response.body)
          usage = data["usage"] || {}
          content_blocks = data["content"] || []

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
    end
  end
end
