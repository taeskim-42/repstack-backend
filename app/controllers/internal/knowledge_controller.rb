# frozen_string_literal: true

module Internal
  class KnowledgeController < BaseController
    skip_before_action :set_user, only: [:search]

    # GET /internal/knowledge/search?query=...&limit=5&knowledge_types=exercise_technique
    def search
      query = params[:query]
      return render_error("query 파라미터가 필요합니다.") if query.blank?

      results = RagSearchService.search(
        query,
        limit: (params[:limit] || 5).to_i,
        knowledge_types: params[:knowledge_types]&.split(","),
        filters: {
          exercise_name: params[:exercise_name],
          muscle_group: params[:muscle_group],
          difficulty_level: params[:difficulty_level]
        }.compact
      )

      render_success(
        results: results,
        count: results.size,
        context_prompt: RagSearchService.build_context_prompt(results)
      )
    end
  end
end
