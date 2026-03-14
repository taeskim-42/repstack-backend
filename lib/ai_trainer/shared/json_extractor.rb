# frozen_string_literal: true

module AiTrainer
  module Shared
    module JsonExtractor
      # Extract JSON from LLM response text (handles markdown code blocks)
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
    end
  end
end
