# frozen_string_literal: true

# AgentBridge: HTTP client for the Python Agent Service.
# Delegates chat processing to the Claude Agent SDK-based service.
# Falls back to legacy ChatService on failure.
class AgentBridge
  AGENT_SERVICE_URL = ENV["AGENT_SERVICE_URL"]
  AGENT_API_TOKEN = ENV["AGENT_API_TOKEN"]
  TIMEOUT = 60 # seconds

  # Map tool names to iOS-compatible intent strings
  TOOL_TO_INTENT = {
    "generate_routine" => "GENERATE_ROUTINE",
    "replace_exercise" => "REPLACE_EXERCISE",
    "add_exercise" => "ADD_EXERCISE",
    "delete_exercise" => "DELETE_EXERCISE",
    "record_exercise" => "RECORD_EXERCISE",
    "check_condition" => "CHECK_CONDITION",
    "complete_workout" => "WORKOUT_COMPLETED",
    "submit_feedback" => "FEEDBACK_RECEIVED",
    "explain_plan" => "EXPLAIN_LONG_TERM_PLAN",
    "get_today_routine" => "GENERATE_ROUTINE"
  }.freeze

  # Tools that are informational (not primary actions)
  # NOTE: get_today_routine excluded — it returns routine data that needs GENERATE_ROUTINE intent
  INFO_TOOLS = %w[get_user_profile get_training_history read_memory write_memory search_fitness_knowledge].freeze

  # Intent-specific default suggestions (override LLM-generated ones)
  INTENT_SUGGESTIONS = {
    "GENERATE_ROUTINE" => [ "운동 끝났어", "운동 설명 더 자세히 알려줘", "운동 바꾸고 싶어" ],
    "CHECK_CONDITION" => [ "오늘 루틴 만들어줘", "컨디션 다시 체크할게" ],
    "WORKOUT_COMPLETED" => [ "오늘 운동 어땠어?", "다음 루틴 만들어줘" ],
    "FEEDBACK_RECEIVED" => [ "다음 루틴 만들어줘", "감사합니다" ]
  }.freeze

  class << self
    def process(user:, message:, routine_id: nil, session_id: nil)
      return legacy_fallback(user, message, routine_id, session_id) unless available?

      response = post_chat(
        user_id: user.id,
        message: message,
        routine_id: routine_id,
        session_id: session_id
      )

      parse_response(response, user)
    rescue Net::ReadTimeout, Net::OpenTimeout => e
      Rails.logger.error("[AgentBridge] Timeout: #{e.message}")
      legacy_fallback(user, message, routine_id, session_id)
    rescue StandardError => e
      Rails.logger.error("[AgentBridge] Error: #{e.class} - #{e.message}")
      legacy_fallback(user, message, routine_id, session_id)
    end

    def available?
      AGENT_SERVICE_URL.present? && AGENT_API_TOKEN.present?
    end

    def healthy?
      return false unless available?

      uri = URI("#{AGENT_SERVICE_URL}/health")
      response = Net::HTTP.get_response(uri)
      response.is_a?(Net::HTTPSuccess)
    rescue StandardError
      false
    end

    def session_status(user_id)
      return nil unless available?

      uri = URI("#{AGENT_SERVICE_URL}/sessions/#{user_id}/status")
      request = Net::HTTP::Get.new(uri)
      request["Authorization"] = "Bearer #{AGENT_API_TOKEN}"

      response = make_request(uri, request)
      JSON.parse(response.body, symbolize_names: true) if response.is_a?(Net::HTTPSuccess)
    rescue StandardError
      nil
    end

    def reset_session(user_id)
      return false unless available?

      uri = URI("#{AGENT_SERVICE_URL}/sessions/#{user_id}/reset")
      request = Net::HTTP::Post.new(uri)
      request["Authorization"] = "Bearer #{AGENT_API_TOKEN}"
      request["Content-Type"] = "application/json"

      response = make_request(uri, request)
      response.is_a?(Net::HTTPSuccess)
    rescue StandardError
      false
    end

    private

    def post_chat(user_id:, message:, routine_id:, session_id:)
      uri = URI("#{AGENT_SERVICE_URL}/chat")
      request = Net::HTTP::Post.new(uri)
      request["Authorization"] = "Bearer #{AGENT_API_TOKEN}"
      request["Content-Type"] = "application/json"
      request.body = {
        user_id: user_id,
        message: message,
        routine_id: routine_id,
        session_id: session_id
      }.compact.to_json

      make_request(uri, request)
    end

    def make_request(uri, request)
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = uri.scheme == "https"
      http.open_timeout = 5
      http.read_timeout = TIMEOUT
      http.request(request)
    end

    def parse_response(response, user = nil)
      unless response.is_a?(Net::HTTPSuccess)
        Rails.logger.error("[AgentBridge] HTTP #{response.code}: #{response.body}")
        return nil
      end

      data = JSON.parse(response.body, symbolize_names: true)
      tool_calls = data[:tool_calls] || []
      message_text = data[:message] || ""

      # Derive intent + structured data from tool_calls
      intent, structured_data = extract_intent_and_data(tool_calls)

      # Fallback: detect routine content in GENERAL_CHAT text
      if intent == "GENERAL_CHAT" && routine_text_detected?(message_text)
        fallback_routine = find_today_routine_for_user(user)
        if fallback_routine
          intent = "GENERATE_ROUTINE"
          structured_data = structured_data.merge(routine: fallback_routine)
          Rails.logger.warn("[AgentBridge] Fallback: text contained routine content, overriding to GENERATE_ROUTINE")
        end
      end

      # Use intent-specific default suggestions, fallback to LLM-extracted ones
      suggestions = INTENT_SUGGESTIONS[intent] || extract_suggestions(message_text)
      structured_data[:suggestions] = suggestions if suggestions.any?

      # Strip suggestions text from display message
      clean_message = strip_suggestions_text(message_text)

      # Strip markdown (iOS compatibility)
      clean_message = clean_message&.gsub(/\*\*([^*]*)\*\*/, '\1')&.gsub(/^##\s+/, "")

      {
        success: data[:success] != false,
        message: clean_message,
        intent: intent,
        data: structured_data,
        error: data[:error],
        agent_session_id: data[:session_id],
        cost_usd: calculate_cost(data.dig(:usage, :input_tokens), data.dig(:usage, :output_tokens)),
        tokens_used: (data.dig(:usage, :input_tokens) || 0) + (data.dig(:usage, :output_tokens) || 0)
      }
    rescue JSON::ParserError => e
      Rails.logger.error("[AgentBridge] JSON parse error: #{e.message}")
      nil
    end

    def extract_intent_and_data(tool_calls)
      return [ "GENERAL_CHAT", {} ] if tool_calls.empty?

      # Find the last "action" tool call (skip info tools like read_memory, get_profile)
      primary_call = tool_calls.reverse.find { |tc| INFO_TOOLS.exclude?(tc[:name]) }
      primary_call ||= tool_calls.last

      tool_name = primary_call[:name]
      intent = TOOL_TO_INTENT[tool_name] || "GENERAL_CHAT"
      result = primary_call[:result] || {}

      # Extract structured data from tool result
      structured = result.is_a?(Hash) ? result.deep_symbolize_keys : {}

      # Normalize get_today_routine response to match AiRoutineType format
      if tool_name == "get_today_routine" && structured[:routine].is_a?(Hash)
        structured[:routine] = normalize_routine_format(structured[:routine])
      end

      [ intent, structured ]
    end

    # Convert UsersController format_routine → AiRoutineType-compatible format
    def normalize_routine_format(routine)
      normalized = routine.dup

      # Map :id → :routine_id (UsersController uses :id, AiRoutineType expects :routine_id)
      normalized[:routine_id] ||= normalized.delete(:id)&.to_s
      normalized[:tier] ||= "beginner"
      normalized[:user_level] ||= 1
      normalized[:fitness_factor] ||= normalized[:workout_type] || "strength"
      normalized[:fitness_factor_korean] ||= normalized[:workout_type] || "근력"
      normalized[:estimated_duration_minutes] ||= normalized[:estimated_duration] || 45
      normalized[:generated_at] ||= Time.current.iso8601

      # Map day_number → day_korean
      unless normalized[:day_korean]
        day_names = %w[일요일 월요일 화요일 수요일 목요일 금요일 토요일]
        normalized[:day_korean] = day_names[normalized[:day_number].to_i] || "월요일"
      end

      # Normalize exercises
      if normalized[:exercises].is_a?(Array)
        normalized[:exercises] = normalized[:exercises].map do |ex|
          ex = ex.dup
          ex[:exercise_id] ||= ex.delete(:id)&.to_s
          ex[:order] ||= (ex[:order_index] || 0) + 1
          ex[:target_muscle] ||= "전신"
          ex[:rest_seconds] ||= ex[:rest_duration_seconds]
          ex[:instructions] ||= ex[:how_to]
          ex[:target_weight_kg] ||= ex[:weight]&.to_f if ex[:weight].present?
          ex
        end
      end

      normalized
    end

    def extract_suggestions(message)
      return [] if message.blank?

      # Pattern: suggestions: ["a", "b", "c"]
      if message =~ /suggestions:\s*-?\s*\[([^\]]+)\]/i
        items = Regexp.last_match(1).scan(/"([^"]+)"/).flatten
        return items.first(4) if items.length >= 2
      end

      []
    end

    def strip_suggestions_text(message)
      return message if message.blank?

      cleaned = message.dup
      # Strip "---" separator + suggestions block at end of message
      cleaned.gsub!(/\n*-{2,}\s*\n*suggestions\s*[:：\-]?\s*-?\s*\[.*?\]\s*\z/mi, "")
      # Strip standalone suggestions line anywhere
      cleaned.gsub!(/[[:space:]]*suggestions\s*[:：\-]?\s*-?\s*\[.*?\]/mi, "")
      cleaned.gsub!(/[[:space:]]*suggestions\s*[:：]\s*[^\[].*/mi, "")
      # Clean trailing "---" separator left behind
      cleaned.gsub!(/\n*-{2,}\s*\z/m, "")
      cleaned.strip
    end

    def calculate_cost(input_tokens, output_tokens)
      return nil unless input_tokens && output_tokens

      # Sonnet 4.5 pricing: $3/M input, $15/M output
      ((input_tokens * 3.0 + output_tokens * 15.0) / 1_000_000).round(6)
    end

    def routine_text_detected?(text)
      return false if text.blank?

      exercise_keywords = %w[세트 회 렙 rep set]
      keyword_count = exercise_keywords.count { |kw| text.include?(kw) }

      keyword_count >= 2 && text.count("\n") >= 3
    end

    def find_today_routine_for_user(user)
      return nil unless user

      routine = user.workout_routines
                    .where(created_at: Time.current.beginning_of_day..Time.current.end_of_day)
                    .where(is_completed: false)
                    .order(created_at: :desc)
                    .first
      return nil unless routine

      normalize_routine_format(format_routine_for_response(routine))
    rescue StandardError => e
      Rails.logger.error("[AgentBridge] Fallback routine lookup failed: #{e.message}")
      nil
    end

    def format_routine_for_response(routine)
      {
        id: routine.id,
        name: "#{routine.day_of_week} #{routine.workout_type}",
        day_number: routine.day_number,
        estimated_duration: routine.estimated_duration,
        workout_type: routine.workout_type,
        exercises: routine.routine_exercises.order(:order_index).map { |re|
          {
            id: re.id,
            exercise_name: re.exercise_name,
            sets: re.sets,
            reps: re.reps,
            weight_description: re.weight_description,
            how_to: re.how_to,
            target_muscle: re.target_muscle,
            order_index: re.order_index
          }
        }
      }
    end

    def legacy_fallback(user, message, routine_id, session_id)
      Rails.logger.info("[AgentBridge] Falling back to legacy ChatService")
      ChatService.process(
        user: user,
        message: message,
        routine_id: routine_id,
        session_id: session_id
      )
    end
  end
end
