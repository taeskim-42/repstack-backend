# frozen_string_literal: true

module Internal
  class KnowledgeController < BaseController
    skip_before_action :set_user, only: [ :search, :exercise_clips ]

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

    # GET /internal/knowledge/exercise_clips?exercise_name=bench_press&locale=ko
    def exercise_clips
      exercise_name = params[:exercise_name]
      return render_error("exercise_name 파라미터가 필요합니다.") if exercise_name.blank?

      locale = params[:locale] || "ko"
      limit = (params[:limit] || 5).to_i

      clips = ExerciseVideoClipService.clips_for_exercise(exercise_name, locale: locale, limit: limit)

      render_success(
        clips: clips.map { |c| ExerciseVideoClipService.format_clip_reference(c) },
        count: clips.size
      )
    end
  end
end
