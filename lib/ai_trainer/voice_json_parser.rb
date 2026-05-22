# frozen_string_literal: true

module AiTrainer
  # Shared utility for stripping markdown fences and locating the JSON object
  # in an LLM response. Extracted from voice_normalizer_service.rb,
  # condition_service.rb, and condition/response_parser.rb (D13 / R15).
  #
  # Two functions:
  #   - extract(text): returns a candidate JSON substring (best-effort,
  #     never raises). Callers JSON.parse themselves and rescue.
  #   - parse(text): convenience wrapper that returns the parsed hash or
  #     nil if parsing fails. Use this for callers that just want a hash.
  module VoiceJsonParser
    FENCED_JSON_RE = /```(?:json)?\s*(\{.*?\})\s*```/m

    module_function

    # Best-effort JSON extraction from an LLM response. Handles:
    #   - ```json ... ``` fences
    #   - ``` ... ``` fences
    #   - bare {...} embedded in prose
    #   - raw JSON
    def extract(text)
      return text if text.nil?

      if (match = text.match(FENCED_JSON_RE))
        return match[1]
      end

      start_idx = text.index("{")
      end_idx = text.rindex("}")
      return text[start_idx..end_idx] if start_idx && end_idx && end_idx > start_idx

      # No braces at all — strip fences and trim as a last resort
      text.gsub(/```json\n?/, "").gsub(/```\n?/, "").strip
    end

    # Returns parsed hash or nil on parse failure.
    def parse(text)
      JSON.parse(extract(text))
    rescue JSON::ParserError
      nil
    end
  end
end
