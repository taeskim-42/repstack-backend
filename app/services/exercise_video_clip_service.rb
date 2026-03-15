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
