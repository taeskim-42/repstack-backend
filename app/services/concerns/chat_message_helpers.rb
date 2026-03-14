# frozen_string_literal: true

# Extracted from ChatService: suggestion extraction, suggestion text stripping,
# semantic response cache, and exercise lookup helpers.
module ChatMessageHelpers
  extend ActiveSupport::Concern

  private

  # ============================================
  # Semantic Response Cache (Vector Similarity)
  # ============================================

  def get_cached_response
    return nil if message.blank? || message.length < 10

    cached = ChatResponseCache.find_similar(message)
    return cached.answer if cached

    nil
  rescue => e
    Rails.logger.error("[ChatService] Cache lookup error: #{e.message}")
    nil
  end

  def cache_response(answer)
    return if answer.blank? || message.blank? || message.length < 10

    ChatResponseCache.cache_response(question: message, answer: answer)
  rescue => e
    Rails.logger.error("[ChatService] Cache save error: #{e.message}")
  end

  # ============================================
  # Suggestion Extraction
  # ============================================

  # Extract choice options from AI message for button display
  def extract_suggestions_from_message(message)
    return [] if message.blank?

    suggestions = try_suggestions_pattern(message) ||
                  try_emoji_pattern(message) ||
                  try_question_pattern(message) ||
                  try_paren_pattern(message) ||
                  try_numbered_pattern(message)

    suggestions || []
  end

  # Strip "suggestions: ..." text from message so it doesn't show in chat
  # Handles various LLM output formats: unicode spaces, missing colon, hyphen prefix, etc.
  def strip_suggestions_text(message)
    return message if message.blank?

    cleaned = message.dup

    # "suggestions: [...]" anywhere (with unicode spaces, optional colon/hyphen)
    cleaned.gsub!(/[[:space:]]*suggestions\s*[:：\-]?\s*-?\s*\[.*?\]/mi, "")
    # "suggestions:" followed by rest of message (no bracket, free-form text)
    cleaned.gsub!(/[[:space:]]*suggestions\s*[:：]\s*[^\[].*/mi, "")
    # Trailing numbered lists that look like suggestions
    cleaned.gsub!(/\n+(?:\d+[.)\-]\s*[^\n]+\n*){2,}\z/m, "")
    # Orphaned markdown bold/italic markers
    cleaned.gsub!(/\s*\*{1,3}\s*\z/, "")

    cleaned.strip
  end

  # ============================================
  # Routine Helpers
  # ============================================

  # Check if routine can be edited (only today's routine is editable)
  def routine_editable?(routine)
    return false unless routine
    routine.created_at >= Time.current.beginning_of_day
  end

  def current_routine
    return @current_routine if defined?(@current_routine)

    @current_routine = if routine_id.present?
      lookup_routine_by_id
    end
  end

  def find_exercise_in_routine(routine, exercise_name)
    return nil unless exercise_name.present?

    name_lower = exercise_name.downcase.gsub(/\s+/, "")
    exercises = routine.routine_exercises.reload

    Rails.logger.info("[ChatService] Looking for '#{exercise_name}' in routine #{routine.id}")
    Rails.logger.info("[ChatService] Routine has #{exercises.count} exercises: #{exercises.map(&:exercise_name).join(', ')}")

    found = exercises.find do |ex|
      ex_name = ex.exercise_name.to_s.downcase.gsub(/\s+/, "")
      ex_name.include?(name_lower) || name_lower.include?(ex_name)
    end

    Rails.logger.info("[ChatService] Found exercise: #{found&.exercise_name || 'nil'}")
    found
  end

  # ============================================
  # Response builders
  # ============================================

  def success_response(message:, intent:, data:)
    clean_msg = strip_suggestions_text(message)

    # Strip markdown — iOS app doesn't render markdown bold/headers
    clean_msg = clean_msg&.gsub(/\*\*([^*]*)\*\*/, '\1')
                         &.gsub(/^##\s+/, "")
    { success: true, message: clean_msg, intent: intent, data: data, error: nil }
  end

  def error_response(error_message)
    { success: false, message: nil, intent: nil, data: nil, error: error_message }
  end

  def try_suggestions_pattern(msg)
    return unless msg =~ /suggestions:\s*-?\s*\[([^\]]+)\]/i

    items = $1.scan(/"([^"]+)"/).flatten
    items.first(4) if items.length >= 2
  end

  def try_emoji_pattern(msg)
    emoji_matches = msg.scan(/([1-9]️⃣[^\n]+)/).flatten
    return unless emoji_matches.length >= 2

    result = emoji_matches.map { |m| m.gsub(/^[1-9]️⃣\s*/, "").strip }
    result.first(4) if result.any?
  end

  def try_question_pattern(msg)
    return unless msg =~ /([가-힣a-zA-Z0-9]+)\?\s*([가-힣a-zA-Z0-9]+)\?/

    result = [$1, $2]
    result if result.length >= 2
  end

  def try_paren_pattern(msg)
    paren_matches = msg.scan(/\(([^)]+[\/,][^)]+)\)/).flatten
    paren_matches.each do |match|
      options = match.split(%r{[/,]}).map(&:strip).reject(&:blank?)
      return options.first(4) if options.length >= 2
    end
    nil
  end

  def try_numbered_pattern(msg)
    matches = msg.scan(/\d+\.\s*([^\d\n]+?)(?=\s*\d+\.|$)/).flatten.map(&:strip).reject(&:blank?)
    matches.first(4) if matches.length >= 2
  end

  def lookup_routine_by_id
    found = user.workout_routines.find_by(id: routine_id)

    # Fallback: AI-generated "RT-{level}-{timestamp}-{hex}" format
    if found.nil? && routine_id.to_s.start_with?("RT-")
      Rails.logger.warn("[ChatService] Routine ID '#{routine_id}' is AI-generated format, attempting fallback lookup")

      if routine_id =~ /RT-\d+-(\d+)-/
        timestamp = Regexp.last_match(1).to_i
        time_range = Time.at(timestamp - 300)..Time.at(timestamp + 300)
        found = user.workout_routines.where(created_at: time_range).order(created_at: :desc).first
        Rails.logger.info("[ChatService] Found routine by timestamp range: #{found&.id}")
      end

      found ||= user.workout_routines.where(is_completed: false).order(created_at: :desc).first
    end

    found
  end
end
