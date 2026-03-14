# frozen_string_literal: true

module AiTrainer
  module LevelAssessment
    # Parses LLM responses and merges collected data.
    # All methods access instance variables via the host class.
    module ResponseParser
      include AssessmentConstants

      ESSENTIAL_FIELDS = %w[experience frequency goals environment injuries schedule program_duration].freeze

      def parse_response(llm_response, user_message)
        content = llm_response[:content]
        json_match = content.match(/\{[\s\S]*\}/)

        if json_match
          parse_json_response(json_match[0], user_message, content)
        else
          parse_plain_text_response(content, user_message)
        end
      rescue JSON::ParserError => e
        Rails.logger.warn("[LevelAssessmentService] JSON parse error: #{e.message}. Preserving existing data.")
        parse_plain_text_response(content, user_message)
      end

      # Check if user message signals they want a routine now
      def user_wants_routine?(message)
        return false if message.blank?

        message_lower = message.downcase.strip
        return true if explicit_routine_patterns.any? { |p| message_lower.include?(p) }
        return false if question_pattern?(message_lower)
        return true if action_patterns.any? { |p| message_lower.include?(p) }
        return true if message_lower.length < 10 && short_confirmations.any? { |w| message_lower == w }

        false
      end

      # Strip "suggestions: [...]" and numbered lists embedded in the message field
      def strip_suggestions_from_message(msg)
        return msg if msg.blank?

        cleaned = msg.dup
        cleaned.gsub!(/[[:space:]]*suggestions\s*:?\s*-?\s*\[.*?\]/mi, "")
        cleaned.gsub!(/\n+(?:\d+[.)\-]\s*[^\n]+\n*){2,}\z/m, "")
        cleaned.strip
      end

      def build_consultation_summary(collected)
        parts = []
        parts << translate_experience(collected["experience"]) if collected["experience"]
        parts << "#{collected['goals']} 목표" if collected["goals"]
        parts << "주 #{collected['frequency']} 운동" if collected["frequency"]
        parts << collected["environment"].to_s if collected["environment"]
        parts << "집중 부위: #{collected['focus_areas']}" if collected["focus_areas"]
        parts << "주의: #{collected['injuries']}" if collected["injuries"] && collected["injuries"] != "없어요"
        parts.join(", ")
      end

      # Ask LLM to generate contextual suggestions for a plain-text message
      def generate_suggestions_for_plain_text(message_text)
        return [] if message_text.blank?

        Rails.logger.info("[LevelAssessmentService] Generating suggestions for plain text via LLM")
        response = LlmGateway.chat(
          prompt: message_text,
          task: :level_assessment,
          messages: [
            { role: "user", content: "다음 트레이너의 질문/메시지에 대해 사용자가 탭해서 답할 수 있는 선택지를 2-4개 JSON 배열로만 반환하세요. 다른 텍스트 없이 배열만 출력하세요.\n\n트레이너: #{message_text}" }
          ],
          system: "JSON 배열만 반환하세요. 예: [\"아침형\", \"저녁형\", \"상관없어\"]. 다른 텍스트나 설명 없이 JSON 배열만 출력하세요."
        )

        return [] unless response[:success]

        extract_suggestions_array(response[:content].strip)
      rescue => e
        Rails.logger.warn("[LevelAssessmentService] Failed to generate suggestions for plain text: #{e.message}")
        []
      end

      private

      def parse_json_response(raw_json, user_message, _content)
        data = JSON.parse(raw_json)

        collected = get_collected_data
        form_data = extract_form_data
        history = collected["conversation_history"] || []

        llm_collected = (data["collected_data"] || {}).except("conversation_history")
        new_collected = merge_collected_data(form_data, collected, llm_collected)

        Rails.logger.info("[LevelAssessmentService] LLM collected_data: #{llm_collected.inspect}")

        is_complete = resolve_completion(data, user_message, new_collected)
        data["message"] = build_auto_complete_message(new_collected) if all_essential_collected?(new_collected) && !is_complete
        is_complete = true if all_essential_collected?(new_collected)

        build_assessment_if_needed(data, new_collected, user_message, is_complete)

        # Append current turn to history
        new_collected["conversation_history"] = append_to_history(history, user_message, data["message"])

        extract_inline_suggestions(data)
        clean_message = strip_suggestions_from_message(data["message"])

        build_result(clean_message, data, new_collected, is_complete)
      end

      def parse_plain_text_response(content, user_message)
        Rails.logger.warn("[LevelAssessmentService] LLM returned plain text, not JSON. Preserving existing data.")

        collected = get_collected_data
        form_data = extract_form_data
        history = collected["conversation_history"] || []
        new_collected = form_data.merge(collected.except("conversation_history"))

        is_complete = user_wants_routine?(user_message) || all_essential_collected?(new_collected)
        suggestions, final_message = extract_suggestions_from_plain_text(content)

        if is_complete
          assessment = build_fallback_assessment(new_collected)
          final_message = "좋아요! 상담 내용을 바탕으로 딱 맞는 루틴을 만들어드릴게요! 💪"
        end

        new_collected["conversation_history"] = append_to_history(history, user_message, final_message)

        {
          message: final_message,
          next_state: is_complete ? STATES[:completed] : STATES[:asking_experience],
          collected_data: new_collected,
          is_complete: is_complete,
          assessment: is_complete ? assessment : nil,
          suggestions: suggestions.presence || generate_suggestions_for_plain_text(final_message)
        }
      end

      def merge_collected_data(form_data, collected, llm_collected)
        # Priority: existing collected > form_data; LLM fills blanks only
        merged = form_data.merge(collected.except("conversation_history")) { |_k, old, new_val| old.presence || new_val }
        llm_collected.each { |k, v| merged[k] = v if merged[k].blank? && v.present? }
        merged
      end

      def resolve_completion(data, user_message, new_collected)
        is_complete = data["is_complete"] || false
        is_complete = true if user_wants_routine?(user_message)
        is_complete
      end

      def all_essential_collected?(collected)
        ESSENTIAL_FIELDS.all? { |f| collected[f].present? }
      end

      def build_assessment_if_needed(data, new_collected, user_message, is_complete)
        return unless is_complete && data["assessment"].blank?

        experience_level = new_collected["experience"] || "intermediate"
        data["assessment"] = {
          "experience_level" => experience_level,
          "fitness_goal" => new_collected["goals"],
          "summary" => build_consultation_summary(new_collected)
        }
        data["message"] = "좋아요! 상담 내용을 바탕으로 딱 맞는 루틴을 만들어드릴게요! 💪" if user_wants_routine?(user_message)
      end

      def build_fallback_assessment(collected)
        {
          "experience_level" => collected["experience"] || "intermediate",
          "numeric_level" => nil,
          "fitness_goal" => collected["goals"],
          "summary" => build_consultation_summary(collected)
        }
      end

      def append_to_history(history, user_message, assistant_message)
        new_history = history.dup
        new_history << { "role" => "user", "content" => user_message } if user_message.present?
        new_history << { "role" => "assistant", "content" => assistant_message } if assistant_message.present?
        new_history
      end

      def extract_inline_suggestions(data)
        return unless Array(data["suggestions"]).empty? && data["message"].present?

        extracted = data["message"].scan(/suggestions\s*:?\s*-?\s*\[([^\]]+)\]/i).flatten.first
        return unless extracted

        items = extracted.scan(/"([^"]+)"/).flatten
        data["suggestions"] = items.first(4) if items.length >= 2
      end

      def extract_suggestions_from_plain_text(text)
        final_message = text.dup
        suggestions = []
        if final_message =~ /suggestions:\s*-?\s*\[([^\]]+)\]/i
          suggestions = $1.scan(/"([^"]+)"/).flatten.first(4)
          final_message = final_message.gsub(/\n*suggestions:\s*-?\s*\[[^\]]*\]\s*/i, "").strip
        end
        [ suggestions, final_message ]
      end

      def extract_suggestions_array(content)
        return JSON.parse(content).then { |p| Array(p).map(&:to_s).first(4) } if content.start_with?("[")

        if content =~ /\[([^\]]+)\]/
          items = $1.scan(/"([^"]+)"/).flatten
          return items.first(4) if items.length >= 2
        end
        []
      rescue JSON::ParserError
        []
      end

      def build_result(message, data, new_collected, is_complete)
        assessment = data["assessment"]
        if assessment.is_a?(Hash)
          assessment = assessment.merge("numeric_level" => nil) unless assessment.key?("numeric_level")
        end

        {
          message: message,
          next_state: data["next_state"] || STATES[:asking_experience],
          collected_data: new_collected,
          is_complete: is_complete,
          assessment: assessment,
          suggestions: Array(data["suggestions"]).first(4)
        }
      end

      def explicit_routine_patterns
        [
          "루틴 만들어줘", "루틴 만들어주세요", "루틴 만들어 주세요",
          "루틴 짜줘", "루틴 짜주세요", "루틴 짜 주세요",
          "루틴을 만들어줘", "루틴을 만들어주세요",
          "루틴이요", "루틴 부탁",
          "이제 됐", "이제 충분", "됐어 만들어", "충분해", "그만 물어", "그만 질문"
        ]
      end

      def action_patterns
        %w[만들어줘 만들어주세요 만들어\ 주세요 짜줘 짜주세요 시작하자 시작할게 바로\ 시작]
      end

      def short_confirmations
        %w[네 응 좋아 그래 오케이 ㅇㅋ ok 알겠어 됐어 충분]
      end

      def question_pattern?(message_lower)
        message_lower.end_with?("?") ||
          message_lower =~ /(어\?*|나\?*|까\?*|요\?*|죠\?*)$/ ||
          message_lower.include?("어떻게") ||
          message_lower.include?("뭐가") ||
          message_lower.include?("왜")
      end
    end
  end
end
