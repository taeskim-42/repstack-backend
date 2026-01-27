# frozen_string_literal: true

# AI-powered cleanup service for fitness knowledge chunks
# Uses LLM to determine if content is relevant to fitness/exercise
class KnowledgeCleanupService
  BATCH_SIZE = 20

  class << self
    # Clean up irrelevant knowledge chunks using AI
    # @param limit [Integer] Max chunks to process per call
    # @param dry_run [Boolean] If true, don't delete, just report
    # @return [Hash] Results with deleted count and samples
    def cleanup(limit: 100, dry_run: false)
      chunks = FitnessKnowledgeChunk.order("RANDOM()").limit(limit)
      results = { processed: 0, deleted: 0, kept: 0, deleted_samples: [], errors: [] }

      chunks.each_slice(BATCH_SIZE) do |batch|
        process_batch(batch, results, dry_run)
      end

      results
    end

    private

    def process_batch(batch, results, dry_run)
      summaries = batch.map.with_index do |chunk, idx|
        "#{idx + 1}. [ID:#{chunk.id}] #{chunk.summary || chunk.content&.truncate(150)}"
      end.join("\n")

      prompt = build_prompt(summaries)
      response = call_ai(prompt)

      return results[:errors] << "AI call failed" unless response[:success]

      irrelevant_ids = parse_response(response[:content], batch)

      batch.each do |chunk|
        results[:processed] += 1
        if irrelevant_ids.include?(chunk.id)
          results[:deleted_samples] << { id: chunk.id, summary: chunk.summary&.truncate(100) } if results[:deleted_samples].size < 20
          chunk.destroy unless dry_run
          results[:deleted] += 1
        else
          results[:kept] += 1
        end
      end
    rescue StandardError => e
      results[:errors] << e.message
    end

    def build_prompt(summaries)
      <<~PROMPT
        피트니스 유튜브에서 추출한 지식이다.

        삭제 조건 (모두 충족해야 함):
        1. 운동/훈련/식단/보충제/영양과 전혀 관련 없음
        2. 순수하게 음식 맛이나 요리법만 설명

        삭제 예시:
        - "다금바리 회가 신선하다" (음식 맛)
        - "막창을 구울 때 이렇게 한다" (요리법)

        삭제 금지 (아래 키워드 포함시 무조건 유지):
        운동, 훈련, 식단, 단백질, 탄수화물, 칼로리, 프로틴, 보충제, 부스터,
        염분, 수분, 근육, 회복, 에너지, 체지방, 섭취, 영양

        [항목들]
        #{summaries}

        응답: 순수 음식리뷰/요리법 번호만. 확실하지 않으면 NONE
      PROMPT
    end

    def call_ai(prompt)
      AiTrainer::LlmGateway.chat(
        prompt: prompt,
        task: :knowledge_cleanup,
        system: "피트니스 지식 필터. 운동/식단/영양 관련 키워드가 있으면 절대 선택하지 마라. 순수 음식 맛 리뷰만 선택."
      )
    end

    def parse_response(content, batch)
      return [] if content.strip.upcase == "NONE"

      numbers = content.scan(/\d+/).map(&:to_i)
      numbers.filter_map do |num|
        idx = num - 1
        batch[idx]&.id if idx >= 0 && idx < batch.size
      end
    end
  end
end
