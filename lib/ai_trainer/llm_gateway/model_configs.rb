# frozen_string_literal: true

# Loaded by llm_gateway.rb before the LlmGateway class is defined.
# Uses a plain module name to avoid the AiTrainer::LlmGateway class/module conflict.
module AiTrainer
  module LlmGatewayModelConfigs
    # Model configurations by task type.
    # Organized by cost tier: sonnet (expensive) vs haiku (cost-efficient).
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
        max_tokens: 16384,
        temperature: 0.3
      },

      # Exercise video clip extraction from structured transcripts
      clip_extraction: {
        provider: :anthropic,
        model: "claude-haiku-4-5-20251001",
        max_tokens: 4096,
        temperature: 0.3
      },

      # Exercise replacement suggestion
      exercise_replacement: {
        provider: :anthropic,
        model: "claude-haiku-4-5-20251001",
        max_tokens: 512,
        temperature: 0.5
      },

      # TestFlight feedback classification - minimal output, deterministic
      testflight_analysis: {
        provider: :anthropic,
        model: "claude-haiku-4-5-20251001",
        max_tokens: 256,
        temperature: 0.0
      },

      # Conversation memory extraction - deterministic, structured output
      memory_extraction: {
        provider: :anthropic,
        model: "claude-haiku-4-5-20251001",
        max_tokens: 512,
        temperature: 0.0
      },

      # Long-term program generation (needs good reasoning)
      program_generation: {
        provider: :anthropic,
        model: "claude-sonnet-4-20250514",
        max_tokens: 4096,
        temperature: 0.7
      },

      # Voice input normalization - fast, deterministic
      voice_normalization: {
        provider: :anthropic,
        model: "claude-haiku-4-5-20251001",
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
  end
end
