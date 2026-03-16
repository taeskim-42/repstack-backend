# frozen_string_literal: true

# Direct DB lookup for exercise video clips.
# Replaces vector search for exercise-specific knowledge.
class ExerciseVideoClipService
  class << self
    def clips_for_exercise(name, locale: "ko", limit: 5)
      normalized = normalize(name)
      scope = ExerciseVideoClip.for_exercise(normalized).for_locale(locale)
      scope = ExerciseVideoClip.for_exercise(normalized) if scope.empty?
      scope.order(:clip_type, :timestamp_start).limit(limit)
    end

    # Type-diverse clip selection: picks one clip per type (technique, form_check,
    # pro_tip, common_mistake) then fills remaining slots from different videos.
    def diverse_clips_for_exercise(name, locale: "ko", limit: 3)
      normalized = normalize(name)

      # Try locale-matched first, fallback to all languages
      base_scope = ExerciseVideoClip.for_exercise(normalized)
      locale_scope = base_scope.for_locale(locale)
      scope = locale_scope.exists? ? locale_scope : base_scope

      return [] unless scope.exists?

      # Priority order: technique > form_check > pro_tip > common_mistake
      selected = []

      %w[technique form_check pro_tip common_mistake].each do |type|
        break if selected.size >= limit

        clip = scope.where(clip_type: type)
                    .where.not(youtube_video_id: selected.map(&:youtube_video_id))
                    .order("RANDOM()")
                    .first
        selected << clip if clip
      end

      # Fill remaining slots with clips from different videos
      if selected.size < limit
        remaining = scope.where.not(id: selected.map(&:id))
                         .where.not(youtube_video_id: selected.map(&:youtube_video_id))
                         .order("RANDOM()")
                         .limit(limit - selected.size)
        selected.concat(remaining.to_a)
      end

      selected
    end

    def batch_clips(names, locale: "ko")
      normalized_names = names.map { |n| normalize(n) }
      ExerciseVideoClip
        .where(exercise_name: normalized_names)
        .for_locale(locale)
        .group_by(&:exercise_name)
    end

    def format_clip_reference(clip)
      {
        title: clip.title,
        url: clip.video_url_with_timestamp,
        video_id: clip.video_id,
        channel: clip.channel_name,
        clip_type: clip.clip_type,
        timestamp_start: clip.timestamp_start,
        timestamp_end: clip.timestamp_end,
        summary: clip.summary
      }
    end

    private

    def normalize(name)
      name.to_s.strip.downcase.gsub(/\s+/, "_")
    end
  end
end
