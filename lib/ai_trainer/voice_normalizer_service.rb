# frozen_string_literal: true

module AiTrainer
  class VoiceNormalizerService
    def self.normalize(transcript:, exercise_names:)
      new.normalize(transcript, exercise_names)
    end

    def normalize(transcript, exercise_names)
      response = LlmGateway.chat(
        prompt: user_prompt(transcript, exercise_names),
        task: :voice_normalization,
        system: system_prompt(exercise_names)
      )
      parse_response(response)
    end

    private

    def system_prompt(exercise_names)
      <<~SYSTEM
        You are a workout voice command parser. Parse Korean STT transcripts into JSON.
        STT may have: misrecognized names, missing units, noisy speech.
        Current routine: #{exercise_names.join(', ')}
        Respond with ONLY a JSON object. No markdown, no explanation.
      SYSTEM
    end

    def user_prompt(transcript, exercise_names)
      <<~PROMPT
        "#{transcript}"
        → {"exercise":"...","weight":number|null,"reps":integer|null,"sets":integer|null,"intent":"record_set"|"undo_last_set"|"end_workout"|"next_exercise"|"status_check"}
        Rules: fuzzy match exercise to [#{exercise_names.join(', ')}]. Two bare numbers = weight(kg), reps. 취소/되돌→undo_last_set. 끝/종료→end_workout. 다음→next_exercise. 몇세트/얼마나→status_check. Default: record_set.
      PROMPT
    end

    def parse_response(response)
      return { success: false, error: "LLM 호출 실패" } unless response[:success]

      json = JSON.parse(
        response[:content].gsub(/```json\n?/, "").gsub(/```\n?/, "").strip
      )
      {
        success: true,
        exercise: json["exercise"],
        weight: json["weight"]&.to_f,
        reps: json["reps"]&.to_i,
        sets: json["sets"]&.to_i,
        intent: json["intent"] || "record_set"
      }
    rescue JSON::ParserError
      { success: false, error: "JSON 파싱 실패" }
    end
  end
end
