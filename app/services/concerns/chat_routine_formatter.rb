# frozen_string_literal: true

require_relative "chat_routine_formatter/adjustment_applier"
require_relative "chat_routine_formatter/long_term_plan_builder"

# Extracted from ChatService: routine formatting, long-term plan building,
# weekly split, progression strategy, and routine DB persistence.
module ChatRoutineFormatter
  extend ActiveSupport::Concern

  include AdjustmentApplier
  include LongTermPlanBuilder

  private

  def format_routine_message(routine, program_info = nil)
    msg = "오늘의 루틴을 준비했어요! 💪\n\n"

    if program_info
      phase = program_info[:phase] || program_info["phase"]
      week = program_info[:current_week] || program_info["current_week"]
      total = program_info[:total_weeks] || program_info["total_weeks"]
      if phase && week && total
        msg += "🗓️ **#{program_info[:name] || '프로그램'}** - #{week}/#{total}주차 (#{phase})\n"
      end
    end

    exercises = routine[:exercises] || routine["exercises"] || []
    duration = routine[:estimated_duration_minutes] || routine["estimated_duration_minutes"] || 45

    msg += "📋 **#{routine[:day_korean] || routine['day_korean']}** - #{routine[:fitness_factor_korean] || routine['fitness_factor_korean']}\n"
    msg += "⏱️ 약 #{duration}분 · #{exercises.length}개 운동\n\n"
    msg += "카드를 위로 스와이프하면 상세 내용을 볼 수 있어요.\n"
    msg += "준비되면 알려주세요!"
    msg
  end

  def format_regenerated_routine_message(routine)
    exercises = routine.routine_exercises.order(:order_index)
    duration = routine.estimated_duration || 45

    msg = "루틴을 새로 구성했어요! 🔄\n\n"
    msg += "⏱️ 약 #{duration}분 · #{exercises.length}개 운동\n\n"
    msg += "카드에서 상세 내용을 확인해주세요.\n"
    msg += "준비되면 알려주세요!"
    msg
  end

  def format_routine_for_display(routine)
    return "루틴을 준비하지 못했어요." unless routine

    lines = []
    lines << "📋 **#{routine[:day_korean] || '오늘의 루틴'}**"
    lines << "⏱️ 예상 시간: #{routine[:estimated_duration_minutes] || 60}분"
    lines << ""

    exercises = routine[:exercises] || []
    exercises.each_with_index do |ex, i|
      name = ex[:exercise_name] || ex["exercise_name"]
      sets = ex[:sets] || ex["sets"]
      reps = ex[:reps] || ex["reps"]
      lines << "#{i + 1}. **#{name}** - #{sets}세트 x #{reps}회"
    end

    lines << ""
    lines << "준비되면 '운동 시작'이라고 말씀해주세요! 🔥"

    lines.join("\n")
  end

  def format_long_term_plan_message(long_term_plan, profile)
    name = user.name || "회원"
    goal = profile.fitness_goal || "건강"
    tier = tier_korean(profile.tier || "beginner")

    msg = "## 📋 #{name}님의 맞춤 운동 계획\n\n"
    msg += "**🎯 목표:** #{goal}\n"
    msg += "**💪 레벨:** #{tier}\n"
    msg += "**📅 주간 스케줄:** #{long_term_plan[:weekly_split]}\n\n"

    msg += "### 🗓️ 주간 운동 스케줄\n"
    long_term_plan[:weekly_schedule]&.each do |day|
      day_names = %w[일 월 화 수 목 금 토]
      day_name = day_names[day[:day]] || "#{day[:day]}일"
      msg += "- **#{day_name}요일:** #{day[:focus]}\n"
    end

    msg += "\n### 📈 훈련 전략\n"
    msg += "#{long_term_plan[:description]}\n\n"

    msg += "### 🔥 점진적 과부하\n"
    msg += "#{long_term_plan[:progression_strategy]}\n\n"

    msg += "### ⏰ 예상 결과\n"
    msg += "#{long_term_plan[:estimated_timeline]}\n\n"

    msg += "오늘 운동을 시작해볼까요? \"오늘 루틴 만들어줘\"라고 말씀해주세요! 💪"
    msg
  end

  def format_first_routine_message(routine)
    exercises = routine[:exercises] || routine["exercises"] || []
    duration = routine[:estimated_duration_minutes] || routine["estimated_duration_minutes"] || 45

    msg = "🎯 첫 루틴이 준비됐어요!\n\n"
    msg += "📋 **#{routine[:day_korean] || routine['day_korean']}** - #{routine[:fitness_factor_korean] || routine['fitness_factor_korean'] || '맞춤 훈련'}\n"
    msg += "⏱️ 약 #{duration}분 · #{exercises.length}개 운동\n\n"

    if routine[:notes].present? && routine[:notes].any?
      msg += "💡 **코치 팁:** #{routine[:notes].first}\n\n"
    end

    msg += "카드를 위로 스와이프하면 상세 내용을 볼 수 있어요.\n"
    msg += "준비되면 \"운동 시작\"이라고 말씀해주세요! 💪"
    msg
  end

  # Convert existing DB routine to frontend format
  def format_existing_routine(routine)
    exercises = routine.routine_exercises.order(:order_index).map do |ex|
      {
        exercise_id: ex.id.to_s,
        exercise_name: ex.exercise_name,
        exercise_name_english: ex.exercise_name_english,
        target_muscle: ex.target_muscle,
        target_muscle_korean: ex.target_muscle_korean,
        order: ex.order_index + 1,
        sets: ex.sets,
        reps: ex.reps,
        target_weight_kg: ex.weight,
        weight_description: ex.weight_description,
        weight_guide: ex.weight_guide,
        rest_seconds: ex.rest_duration_seconds,
        instructions: ex.how_to,
        rom: ex.range_of_motion,
        rpe: ex.rpe,
        tempo: ex.tempo,
        bpm: ex.bpm,
        work_seconds: ex.work_seconds,
        equipment: ex.equipment,
        source_program: ex.source_program,
        expert_tips: ex.expert_tips.presence,
        form_cues: ex.form_cues.presence
      }
    end

    {
      routine_id: routine.id.to_s,
      day_of_week: routine.day_number,
      day_korean: routine.day_korean,
      tier: routine.level,
      user_level: user.user_profile&.numeric_level || 1,
      fitness_factor: routine.workout_type,
      fitness_factor_korean: routine.workout_type,
      estimated_duration_minutes: routine.estimated_duration,
      generated_at: routine.created_at.iso8601,
      exercises: exercises,
      training_type: routine.workout_type
    }
  end

  def save_routine_to_db(result)
    today = Date.current
    program = user.active_training_program

    routine = WorkoutRoutine.create!(
      user_id: user.id,
      level: user.user_profile&.tier || "beginner",
      week_number: program&.current_week || 1,
      day_number: today.cwday,
      workout_type: result[:workout_type] || "full_body",
      day_of_week: result[:day_korean] || today.strftime("%A"),
      estimated_duration: result[:estimated_duration_minutes] || 45,
      generated_at: Time.current
    )

    result[:exercises].each_with_index do |ex, idx|
      RoutineExercise.create!(
        workout_routine_id: routine.id,
        exercise_id: ex[:exercise_id] || ex["exercise_id"],
        exercise_name: ex[:exercise_name] || ex["exercise_name"] || ex[:name] || ex["name"],
        exercise_name_english: ex[:exercise_name_english] || ex["exercise_name_english"],
        sets: ex[:sets] || ex["sets"] || 3,
        reps: ex[:reps] || ex["reps"] || 10,
        order_index: idx + 1,
        target_muscle: ex[:target_muscle] || ex["target_muscle"],
        target_muscle_korean: ex[:target_muscle_korean] || ex["target_muscle_korean"],
        rest_duration_seconds: ex[:rest_seconds] || ex["rest_seconds"],
        how_to: ex[:instructions] || ex["instructions"],
        weight: ex[:target_weight_kg] || ex["target_weight_kg"],
        weight_description: ex[:weight_description] || ex["weight_description"],
        weight_guide: ex[:weight_guide] || ex["weight_guide"],
        range_of_motion: ex[:rom] || ex["rom"],
        rpe: ex[:rpe] || ex["rpe"],
        tempo: ex[:tempo] || ex["tempo"],
        bpm: ex[:bpm] || ex["bpm"],
        work_seconds: ex[:work_seconds] || ex["work_seconds"],
        equipment: ex[:equipment] || ex["equipment"],
        source_program: ex[:source_program] || ex["source_program"],
        expert_tips: ex[:expert_tips] || ex["expert_tips"] || [],
        form_cues: ex[:form_cues] || ex["form_cues"] || []
      )
    end

    routine
  rescue => e
    Rails.logger.error("Failed to save routine: #{e.message}")
    nil
  end
end
