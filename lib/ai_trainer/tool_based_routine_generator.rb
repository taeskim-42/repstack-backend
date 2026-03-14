# frozen_string_literal: true

# Facade for the tool-based routine generator.
# All implementation details live in submodules under lib/ai_trainer/tool_based/.
#
# Submodules:
#   PromptBuilder   — system_prompt, build_initial_prompt, build_context, build_program_context, extract_condition_text
#   ToolExecutor    — available_tools, execute_tool, get_routine_data, search_exercises, helpers
#   ResponseParser  — parse_routine_response, fallback_routine, default_exercises, build_default_exercise

require_relative "constants"
require_relative "llm_gateway"
require_relative "workout_programs"
require_relative "exercise_name_normalizer"
require_relative "shared/json_extractor"
require_relative "shared/exercise_finder"
require_relative "shared/time_based_exercise"
require_relative "shared/day_names"
require_relative "shared/muscle_group_mapper"
require_relative "tool_based/training_data"
require_relative "tool_based/prompt_builder"
require_relative "tool_based/tool_executor"
require_relative "tool_based/response_parser"

module AiTrainer
  # Tool-based routine generator using LLM Tool Use.
  # LLM autonomously searches exercises and adjusts training variables.
  class ToolBasedRoutineGenerator
    include Constants
    include ToolBased::TrainingData
    include ToolBased::PromptBuilder
    include ToolBased::ToolExecutor
    include ToolBased::ResponseParser

    def initialize(user:, day_of_week: nil)
      @user = user
      @level = user.user_profile&.numeric_level || 1
      @day_of_week = day_of_week || Time.current.wday
      @day_of_week = 1 if @day_of_week == 0
      @day_of_week = 5 if @day_of_week > 5
      @condition = nil
      @goal = nil
      @tool_calls = []
    end

    def with_condition(condition)
      @condition = condition
      self
    end

    def with_goal(goal)
      @goal = goal
      self
    end

    def generate
      Rails.logger.info("[ToolBasedRoutineGenerator] Starting generation with goal: #{@goal.inspect}")

      context = build_context

      Rails.logger.info("[ToolBasedRoutineGenerator] Calling LLM with tools...")
      response = call_llm_with_tools(context)
      Rails.logger.info(
        "[ToolBasedRoutineGenerator] LLM response: success=#{response[:success]}, " \
        "model=#{response[:model]}, tool_use=#{response[:tool_use].present?}, " \
        "content_length=#{response[:content]&.length}"
      )

      max_iterations = 10
      iteration = 0

      while response[:tool_use] && iteration < max_iterations
        iteration += 1
        Rails.logger.info("[ToolBasedRoutineGenerator] Tool call #{iteration}: #{response[:tool_use][:name]}")

        tool_result = execute_tool(response[:tool_use])
        @tool_calls << {
          tool: response[:tool_use][:name],
          input: response[:tool_use][:input],
          result_preview: tool_result.to_s.truncate(200)
        }

        if tool_result.is_a?(Hash) && tool_result[:rest_day]
          Rails.logger.info("[ToolBasedRoutineGenerator] Rest day - skipping routine generation")
          return build_rest_day_response(tool_result[:message])
        end

        response = continue_with_tool_result(context, response, tool_result)
        Rails.logger.info(
          "[ToolBasedRoutineGenerator] After tool result: success=#{response[:success]}, " \
          "tool_use=#{response[:tool_use].present?}"
        )
      end

      Rails.logger.info("[ToolBasedRoutineGenerator] Final: iterations=#{iteration}, tool_calls=#{@tool_calls.length}")

      if response[:success] && !response[:content].present? && @tool_calls.any?
        Rails.logger.info("[ToolBasedRoutineGenerator] Forcing final JSON response...")
        response = force_final_response(context)
      end

      if response[:success] && response[:content]
        result = parse_routine_response(response[:content])
        result[:tool_calls] = @tool_calls
        result[:generation_method] = "tool_based"
        Rails.logger.info("[ToolBasedRoutineGenerator] Success! exercises=#{result[:exercises]&.length}")
        result
      else
        Rails.logger.warn(
          "[ToolBasedRoutineGenerator] Fallback: success=#{response[:success]}, " \
          "content=#{response[:content].present?}"
        )
        fallback_routine
      end
    rescue StandardError => e
      Rails.logger.error("ToolBasedRoutineGenerator error: #{e.message}\n#{e.backtrace.first(5).join("\n")}")
      fallback_routine
    end

    private

    def default_rest_for_level
      case @level
      when 1..2 then 90
      when 3..5 then 75
      else 60
      end
    end

    def level_to_tier(level)
      case level
      when 1..2 then :beginner
      when 3..5 then :intermediate
      else :advanced
      end
    end

    def tier_korean(tier)
      { beginner: "초급", intermediate: "중급", advanced: "고급" }[tier]
    end

    def assess_condition_state
      return :moderate unless @condition

      energy = @condition[:energy_level] || 3
      sleep  = @condition[:sleep_quality] || 3
      avg    = (energy + sleep) / 2.0

      if avg <= 2
        :low_energy
      elsif avg >= 4
        :high_energy
      else
        :moderate
      end
    end

    def call_llm_with_tools(context)
      LlmGateway.chat(
        prompt: build_initial_prompt(context),
        task: :routine_generation,
        system: system_prompt,
        tools: available_tools
      )
    end

    def continue_with_tool_result(context, previous_response, tool_result)
      messages = [
        { role: "user", content: build_initial_prompt(context) },
        {
          role: "assistant",
          content: [
            {
              type: "tool_use",
              id: previous_response[:tool_use][:id],
              name: previous_response[:tool_use][:name],
              input: previous_response[:tool_use][:input]
            }
          ]
        },
        {
          role: "user",
          content: [
            { type: "tool_result", tool_use_id: previous_response[:tool_use][:id], content: tool_result.to_json }
          ]
        }
      ]

      LlmGateway.chat(
        prompt: "",
        task: :routine_generation,
        system: system_prompt,
        messages: messages,
        tools: available_tools
      )
    end

    def force_final_response(context)
      force_message = <<~MSG
        도구 호출은 충분합니다. 지금까지 수집한 정보를 바탕으로 **즉시 JSON 형식의 최종 루틴을 반환하세요**.
        더 이상 도구를 호출하지 마세요. 바로 JSON을 출력하세요.
      MSG

      LlmGateway.chat(
        prompt: force_message,
        task: :routine_generation,
        system: system_prompt,
        tools: nil
      )
    end
  end
end
