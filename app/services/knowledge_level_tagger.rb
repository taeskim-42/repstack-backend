# frozen_string_literal: true

# Tags fitness knowledge chunks with appropriate difficulty levels
# Levels: beginner, intermediate, advanced, all
class KnowledgeLevelTagger
  BATCH_SIZE = 15

  LEVEL_CRITERIA = {
    beginner: "기본 자세, 동작 방법, 안전 주의사항, 입문자용 팁",
    intermediate: "세부 기술, 변형 동작, 근육별 자극법, 중량 조절",
    advanced: "미세 조정, 고급 테크닉, 전문 팁, 경쟁/대회용",
    all: "모든 레벨에 적용 가능한 일반 정보"
  }.freeze

  class << self
    # Tag chunks with difficulty levels
    # @param limit [Integer] Max chunks to process
    # @return [Hash] Results
    def tag(limit: 100)
      chunks = FitnessKnowledgeChunk
        .where(difficulty_level: [nil, "", "all"])
        .order("RANDOM()")
        .limit(limit)

      results = { processed: 0, tagged: {}, errors: [] }

      chunks.each_slice(BATCH_SIZE) do |batch|
        process_batch(batch, results)
      end

      results
    end

    private

    def process_batch(batch, results)
      summaries = batch.map.with_index do |chunk, idx|
        "#{idx + 1}. #{chunk.summary || chunk.content&.truncate(100)}"
      end.join("\n")

      prompt = build_prompt(summaries)
      response = call_ai(prompt)

      return results[:errors] << "AI call failed" unless response[:success]

      parse_and_apply(response[:content], batch, results)
    rescue StandardError => e
      results[:errors] << e.message
    end

    def build_prompt(summaries)
      <<~PROMPT
        피트니스 지식의 난이도를 분류해줘.

        **레벨 기준:**
        - B (초보자): #{LEVEL_CRITERIA[:beginner]}
        - I (중급자): #{LEVEL_CRITERIA[:intermediate]}
        - A (고급자): #{LEVEL_CRITERIA[:advanced]}
        - X (모든 레벨): #{LEVEL_CRITERIA[:all]}

        [지식 목록]
        #{summaries}

        **응답 형식:** 각 번호에 대해 레벨만 (예: 1:B 2:I 3:A 4:X)
      PROMPT
    end

    def call_ai(prompt)
      AiTrainer::LlmGateway.chat(
        prompt: prompt,
        task: :knowledge_cleanup,
        system: "피트니스 지식 난이도 분류기. B/I/A/X로만 응답."
      )
    end

    def parse_and_apply(content, batch, results)
      # Parse responses like "1:B 2:I 3:A"
      mappings = content.scan(/(\d+)\s*:\s*([BIAX])/i)

      mappings.each do |num_str, level_code|
        idx = num_str.to_i - 1
        next unless idx >= 0 && idx < batch.size

        chunk = batch[idx]
        level = code_to_level(level_code.upcase)

        chunk.update(difficulty_level: level)
        results[:processed] += 1
        results[:tagged][level] ||= 0
        results[:tagged][level] += 1
      end
    end

    def code_to_level(code)
      case code
      when "B" then "beginner"
      when "I" then "intermediate"
      when "A" then "advanced"
      else "all"
      end
    end
  end
end
