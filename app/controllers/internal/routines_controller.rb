# frozen_string_literal: true

module Internal
  class RoutinesController < BaseController
    # POST /internal/routines/generate
    def generate
      profile = @user.user_profile

      unless profile&.onboarding_completed_at.present? || profile&.numeric_level.present?
        return render_error("온보딩이 완료되지 않았습니다.")
      end

      unless profile.numeric_level.present?
        profile.update!(numeric_level: 1, current_level: "beginner")
      end

      today_dow = Time.current.wday == 0 ? 7 : Time.current.wday

      # Check for today's existing incomplete routine
      today_routine = WorkoutRoutine.where(user_id: @user.id)
                                    .where("created_at >= ?", Time.current.beginning_of_day)
                                    .where(day_number: today_dow)
                                    .where(is_completed: false)
                                    .order(created_at: :desc)
                                    .first

      if today_routine
        return render_success(
          routine: format_routine(today_routine),
          source: "existing"
        )
      end

      # Check for baseline from active program
      program = @user.active_training_program
      if program
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

        if baseline&.routine_exercises&.any?
          return render_success(
            routine: format_routine(baseline),
            program: program_info(program),
            source: "baseline"
          )
        end
      end

      # Ensure training program exists
      program ||= ensure_training_program

      # Generate via LLM
      condition = params[:condition].present? ? { notes: params[:condition] } : nil
      recent_feedbacks = @user.workout_feedbacks.order(created_at: :desc).limit(5)

      routine = AiTrainer.generate_routine(
        user: @user,
        day_of_week: today_dow,
        condition_inputs: condition,
        recent_feedbacks: recent_feedbacks,
        goal: params[:goal]
      )

      if routine.is_a?(Hash) && routine[:success] == false
        return render_error(routine[:error] || "루틴 생성 실패")
      end

      if routine.is_a?(Hash) && routine[:rest_day]
        return render_success(rest_day: true, message: routine[:coach_message])
      end

      # Apply stored feedback adjustments (intensity_adjustment from previous sessions)
      routine = apply_feedback_adjustments(routine)

      render_success(
        routine: routine,
        program: program ? program_info(program) : nil,
        source: "generated"
      )
    end

    # POST /internal/routines/replace_exercise
    def replace_exercise
      routine = find_current_routine
      return render_error("루틴을 찾을 수 없습니다.") unless routine
      return render_error("수정 불가능한 루틴입니다.") unless editable?(routine)

      rate_check = RoutineRateLimiter.check_and_increment!(user: @user, action: :exercise_replacement)
      return render_error(rate_check[:error]) unless rate_check[:allowed]

      exercise = find_exercise(routine, params[:exercise_name])
      return render_error("운동을 찾을 수 없습니다.") unless exercise

      replacement = generate_replacement(routine, exercise, params[:reason])
      return render_error(replacement[:error]) unless replacement[:success]

      old_name = exercise.exercise_name
      exercise.update!(
        exercise_name: replacement[:exercise_name],
        sets: replacement[:sets],
        reps: replacement[:reps],
        rest_duration_seconds: replacement[:rest_seconds] || 60,
        how_to: replacement[:instructions],
        weight_description: replacement[:weight_guide]
      )

      render_success(
        routine: format_routine(routine.reload),
        old_exercise: old_name,
        new_exercise: exercise.reload.as_json(only: [:id, :exercise_name, :sets, :reps]),
        remaining_replacements: rate_check[:remaining]
      )
    end

    # POST /internal/routines/add_exercise
    def add_exercise
      routine = find_current_routine
      return render_error("루틴을 찾을 수 없습니다.") unless routine
      return render_error("수정 불가능한 루틴입니다.") unless editable?(routine)

      final_order = (routine.routine_exercises.maximum(:order_index) || -1) + 1
      normalized_name = AiTrainer::ExerciseNameNormalizer.normalize_if_needed(params[:exercise_name])

      exercise = routine.routine_exercises.create!(
        exercise_name: normalized_name,
        order_index: final_order,
        sets: params[:sets] || 3,
        reps: params[:reps] || 10,
        target_muscle: params[:target_muscle],
        rest_duration_seconds: 60
      )

      render_success(
        routine: format_routine(routine.reload),
        added_exercise: exercise.as_json(only: [:id, :exercise_name, :sets, :reps])
      )
    end

    # POST /internal/routines/delete_exercise
    def delete_exercise
      routine = find_current_routine
      return render_error("루틴을 찾을 수 없습니다.") unless routine
      return render_error("수정 불가능한 루틴입니다.") unless editable?(routine)

      exercise = routine.routine_exercises.find_by("exercise_name ILIKE ?", "%#{params[:exercise_name]}%")
      return render_error("운동을 찾을 수 없습니다.") unless exercise

      deleted_name = exercise.exercise_name
      exercise.destroy!

      # Reorder remaining exercises
      routine.routine_exercises.order(:order_index).each_with_index do |ex, idx|
        ex.update!(order_index: idx)
      end

      render_success(
        routine: format_routine(routine.reload),
        deleted_exercise: deleted_name
      )
    end

    private

    def find_current_routine
      if params[:routine_id].present?
        @user.workout_routines.find_by(id: params[:routine_id])
      else
        @user.workout_routines
             .where("created_at >= ?", Time.current.beginning_of_day)
             .where(is_completed: false)
             .order(created_at: :desc)
             .first
      end
    end

    def editable?(routine)
      routine.created_at >= Time.current.beginning_of_day
    end

    def find_exercise(routine, name)
      return nil if name.blank?
      name_lower = name.downcase.gsub(/\s+/, "")
      routine.routine_exercises.detect do |ex|
        ex_name = ex.exercise_name.to_s.downcase.gsub(/\s+/, "")
        ex_name.include?(name_lower) || name_lower.include?(ex_name)
      end
    end

    def generate_replacement(routine, old_exercise, reason)
      other_exercises = routine.routine_exercises
                               .where.not(id: old_exercise.id)
                               .pluck(:exercise_name)

      tier = AiTrainer::Constants.tier_for_level(@user.user_profile&.numeric_level || 1)

      prompt = <<~PROMPT
        ## 교체할 운동
        - 운동명: #{old_exercise.exercise_name}
        - 타겟 근육: #{old_exercise.target_muscle}
        - 세트: #{old_exercise.sets}, 횟수: #{old_exercise.reps}

        ## 교체 이유
        #{reason || "다른 운동으로 변경 원함"}

        ## 조건
        - 사용자 레벨: #{tier}
        - 피해야 할 운동: #{other_exercises.join(', ')}

        JSON으로 대체 운동을 추천해주세요.
      PROMPT

      system = <<~SYSTEM
        전문 피트니스 트레이너입니다. JSON 형식으로만 응답하세요:
        {"exercise_name": "운동명", "sets": 3, "reps": 10, "rest_seconds": 60, "instructions": "방법", "weight_guide": "무게", "reason": "추천 이유"}
      SYSTEM

      response = AiTrainer::LlmGateway.chat(prompt: prompt, task: :exercise_replacement, system: system)
      return { success: false, error: "AI 응답 실패" } unless response[:success]

      json_str = extract_json(response[:content])
      data = JSON.parse(json_str)
      normalized_name = AiTrainer::ExerciseNameNormalizer.normalize_if_needed(data["exercise_name"])
      {
        success: true,
        exercise_name: normalized_name,
        sets: data["sets"] || 3,
        reps: data["reps"] || 10,
        rest_seconds: data["rest_seconds"] || 60,
        instructions: data["instructions"],
        weight_guide: data["weight_guide"]
      }
    rescue JSON::ParserError
      { success: false, error: "응답 파싱 실패" }
    end

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

    # Apply accumulated feedback adjustments to LLM-generated routine
    def apply_feedback_adjustments(routine_data)
      intensity_adj = @user.user_profile&.fitness_factors&.dig("intensity_adjustment") || 0.0
      multiplier = 1.0 + intensity_adj
      return routine_data if (multiplier - 1.0).abs < 0.02

      exercises = routine_data[:exercises] || routine_data["exercises"]
      return routine_data unless exercises.is_a?(Array)

      adjusted = routine_data.dup
      adjusted_key = routine_data.key?(:exercises) ? :exercises : "exercises"
      adjusted[adjusted_key] = exercises.map do |ex|
        adj_ex = ex.dup
        base_reps = ex[:reps] || ex["reps"] || 10
        reps_key = ex.key?(:reps) ? :reps : "reps"
        adj_ex[reps_key] = [(base_reps * multiplier).round, 1].max

        # Adjust weight proportionally (round to nearest 2.5kg)
        base_weight = ex[:target_weight_kg] || ex["target_weight_kg"] || ex[:weight] || ex["weight"]
        if base_weight.is_a?(Numeric) && base_weight > 0
          weight_key = ex.key?(:target_weight_kg) ? :target_weight_kg : (ex.key?(:weight) ? :weight : "weight")
          adj_ex[weight_key] = (base_weight * multiplier / 2.5).round * 2.5
        end

        if (multiplier - 1.0).abs >= 0.15
          base_sets = ex[:sets] || ex["sets"] || 3
          sets_key = ex.key?(:sets) ? :sets : "sets"
          adj_ex[sets_key] = multiplier > 1.0 ? [base_sets + 1, 6].min : [base_sets - 1, 1].max
        end
        adj_ex
      end

      adjusted[:adjusted] = true
      adjusted[:adjustment_multiplier] = multiplier.round(2)
      adjusted
    end

    def format_routine(routine)
      {
        id: routine.id,
        day_of_week: routine.day_of_week,
        day_number: routine.day_number,
        week_number: routine.week_number,
        estimated_duration: routine.estimated_duration,
        workout_type: routine.workout_type,
        is_completed: routine.is_completed,
        exercises: routine.routine_exercises.order(:order_index).map do |ex|
          {
            id: ex.id,
            exercise_name: ex.exercise_name,
            sets: ex.sets,
            reps: ex.reps,
            weight: ex.weight,
            weight_description: ex.weight_description,
            target_muscle: ex.target_muscle,
            rest_duration_seconds: ex.rest_duration_seconds,
            how_to: ex.how_to,
            order_index: ex.order_index
          }
        end
      }
    end

    def program_info(program)
      {
        name: program.name,
        current_week: program.current_week,
        total_weeks: program.total_weeks,
        phase: program.current_phase,
        volume_modifier: program.current_volume_modifier
      }
    end

    def ensure_training_program
      existing = @user.active_training_program
      return existing if existing

      result = AiTrainer::ProgramGenerator.generate(user: @user)
      result[:program] if result[:success]
    rescue StandardError => e
      Rails.logger.error("[Internal::RoutinesController] Program generation failed: #{e.message}")
      nil
    end
  end
end
