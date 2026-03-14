# frozen_string_literal: true

# Tool dispatch, structured command handlers, and shared helpers.
# Included into ChatToolHandlers (and therefore ChatService via include ChatToolHandlers).
module ChatToolHandlers
  module Core
    extend ActiveSupport::Concern

    included do
      # No class-level macros needed
    end

    private

    # ============================================
    # Instant routine shortcut — bypasses LLM entirely
    # Returns nil if no shortcut is possible
    # ============================================
    def try_instant_routine_retrieval
      return nil unless routine_request_message?
      return nil unless user.user_profile&.onboarding_completed_at.present?

      today_dow = Time.current.wday == 0 ? 7 : Time.current.wday

      today_routine = WorkoutRoutine.where(user_id: user.id)
                                    .where("created_at >= ?", Time.current.beginning_of_day)
                                    .where(day_number: today_dow)
                                    .where(is_completed: false)
                                    .order(created_at: :desc)
                                    .first

      if today_routine
        Rails.logger.info("[ChatService] Instant shortcut: today_routine #{today_routine.id}")
        routine_data = format_existing_routine(today_routine)
        return success_response(
          message: "오늘의 루틴이에요! 💪\n\n특정 운동을 바꾸고 싶으면 'XX 대신 다른 운동'이라고 말씀해주세요.",
          intent: "GENERATE_ROUTINE",
          data: { routine: routine_data, suggestions: [] }
        )
      end

      program = user.active_training_program
      return nil unless program

      baseline = program.workout_routines
                        .where(week_number: program.current_week, day_number: today_dow)
                        .where(is_completed: false)
                        .includes(:routine_exercises)
                        .order(created_at: :desc)
                        .first

      if baseline.nil? || baseline.routine_exercises.blank?
        baseline = program.workout_routines
                          .where(week_number: program.current_week)
                          .where(is_completed: false)
                          .includes(:routine_exercises)
                          .order(Arel.sql("ABS(day_number - #{today_dow.to_i})"))
                          .detect { |r| r.routine_exercises.any? }
      end

      return nil unless baseline&.routine_exercises&.any?

      Rails.logger.info("[ChatService] Instant shortcut: baseline #{baseline.id} (week #{program.current_week}, day #{today_dow})")
      routine_data = format_existing_routine(baseline)
      routine_data = apply_routine_adjustments(routine_data)
      program_info = {
        name: program.name,
        current_week: program.current_week,
        total_weeks: program.total_weeks,
        phase: program.current_phase,
        volume_modifier: program.current_volume_modifier
      }
      success_response(
        message: format_routine_message(routine_data, program_info),
        intent: "GENERATE_ROUTINE",
        data: { routine: routine_data, program: program_info, suggestions: [] }
      )
    end

    # ============================================
    # Structured Command Handlers (/start_workout, /end_workout, etc.)
    # ============================================

    def handle_start_workout_command
      active_session = user.workout_sessions.where(end_time: nil).first
      if active_session
        return success_response(
          message: "이미 진행 중인 운동이 있어요! 💪",
          intent: "START_WORKOUT"
        )
      end

      session = user.workout_sessions.create!(
        start_time: Time.current,
        source: "app"
      )

      success_response(
        message: "운동을 시작합니다! 💪 화이팅!",
        intent: "START_WORKOUT",
        data: { session_id: session.id }
      )
    end

    def handle_end_workout_command
      handle_complete_workout({})
    end

    def handle_workout_complete_command
      handle_complete_workout({})
    end

    def handle_check_condition_command
      handle_check_condition({})
    end

    def handle_generate_routine_command
      load_recent_messages
      if (instant = try_instant_routine_retrieval)
        instant
      else
        handle_generate_routine({})
      end
    end

    # Detect routine request messages (conservative: avoid false positives)
    def routine_request_message?
      return false if message.blank?

      msg = message.strip
      return true if msg == "/generate_routine"
      return false if msg.match?(/끝났|완료|대신|바꿔|빼줘|추가|삭제|기록|했어|kg|세트|피드백|컨디션|피곤|아프/)

      msg.match?(/루틴/) || msg.match?(/오늘.{0,4}운동/)
    end

    # ============================================
    # Tool Dispatch
    # ============================================

    def execute_tool(tool_use)
      tool_name = tool_use[:name]
      input = tool_use[:input] || {}

      Rails.logger.info("[ChatService] Executing tool: #{tool_name} with input: #{input}")

      case tool_name
      when "generate_routine"        then handle_generate_routine(input)
      when "check_condition"         then handle_check_condition(input)
      when "record_exercise"         then handle_record_exercise(input)
      when "replace_exercise"        then handle_replace_exercise(input)
      when "add_exercise"            then handle_add_exercise(input)
      when "delete_exercise"         then handle_delete_exercise(input)
      when "explain_long_term_plan"  then handle_explain_long_term_plan(input)
      when "complete_workout"        then handle_complete_workout(input)
      when "submit_feedback"         then handle_submit_feedback(input)
      else error_response("알 수 없는 작업입니다: #{tool_name}")
      end
    end

    # ============================================
    # Shared Helpers
    # ============================================

    # Inline implementation avoids triggering Zeitwerk eager-load of AiTrainer namespace
    # (which has a pre-existing RoutineGenerator class/module conflict).
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

    def infer_target_muscle(exercise_name)
      name_lower = exercise_name.downcase

      mappings = {
        "chest"     => %w[벤치 푸시업 체스트 플라이 딥스],
        "back"      => %w[풀업 로우 렛풀 데드리프트 턱걸이],
        "shoulders" => %w[숄더 프레스 레이즈 어깨],
        "legs"      => %w[스쿼트 런지 레그 프레스 컬 익스텐션],
        "arms"      => %w[컬 바이셉 트라이셉 삼두 이두],
        "core"      => %w[플랭크 크런치 싯업 복근 코어]
      }

      mappings.each do |muscle, keywords|
        return muscle if keywords.any? { |kw| name_lower.include?(kw) }
      end

      "other"
    end

    def parse_condition_string(condition_str)
      return nil if condition_str.blank?

      { notes: condition_str }
    end

    def save_condition_log_from_result(condition)
      return unless condition

      user.condition_logs.create!(
        date: Date.current,
        energy_level: condition[:energy_level] || 3,
        stress_level: condition[:stress_level] || 3,
        sleep_quality: condition[:sleep_quality] || 3,
        motivation: condition[:motivation] || 3,
        soreness: condition[:soreness] || {},
        available_time: condition[:available_time] || 60,
        notes: "Chat에서 입력"
      )
    rescue ActiveRecord::RecordInvalid => e
      Rails.logger.warn("ChatService: Failed to save condition log: #{e.message}")
    end

    def store_today_condition(condition, intensity)
      profile = user.user_profile
      return unless profile

      today = Time.current.to_date.to_s
      factors = profile.fitness_factors || {}
      factors["daily_conditions"] ||= {}
      factors["daily_conditions"][today] = {
        condition: condition.to_s,
        intensity: intensity,
        recorded_at: Time.current.iso8601
      }

      profile.update!(fitness_factors: factors)
    end

    def suggest_today_focus
      day_of_week = Time.current.wday
      recent_sessions = user.workout_sessions
                            .where("start_time > ?", 7.days.ago)
                            .order(start_time: :desc)
                            .limit(7)
      recent_focuses = recent_sessions.map(&:name).compact

      default_split = {
        1 => { focus: "가슴/삼두",      duration: 60 },
        2 => { focus: "등/이두",        duration: 60 },
        3 => { focus: "하체",           duration: 60 },
        4 => { focus: "어깨",           duration: 50 },
        5 => { focus: "가슴/등",        duration: 60 },
        6 => { focus: "하체/코어",      duration: 50 },
        0 => { focus: "휴식 또는 유산소", duration: 30 }
      }

      suggested = default_split[day_of_week]
      if recent_focuses.include?(suggested[:focus])
        all_focuses = [ "가슴", "등", "하체", "어깨", "팔" ]
        least_recent = all_focuses.find { |f| !recent_focuses.any? { |r| r.include?(f) } }
        suggested = { focus: least_recent || "전신", duration: 60 }
      end

      suggested
    end

    # General Chat with RAG
    def handle_general_chat_with_rag
      result = AiTrainer::ChatService.general_chat(
        user: user,
        message: message,
        session_id: session_id
      )

      answer = result[:message] || "무엇을 도와드릴까요?"
      cache_response(answer)

      answer_msg = result[:message] || "무엇을 도와드릴까요?"
      suggestions = extract_suggestions_from_message(answer_msg)
      clean_msg = strip_suggestions_text(answer_msg)

      success_response(
        message: clean_msg,
        intent: "GENERAL_CHAT",
        data: {
          knowledge_used: result[:knowledge_used],
          session_id: result[:session_id],
          suggestions: suggestions.presence || [
            "오늘 루틴 만들어줘",
            "내 운동 계획 알려줘",
            "더 궁금한 거 있어"
          ]
        }
      )
    end
  end
end
