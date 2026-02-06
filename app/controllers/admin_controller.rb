# frozen_string_literal: true

# Admin controller for background job triggers
# Protected by admin secret token
class AdminController < ApplicationController
  skip_before_action :authorize_request
  before_action :verify_admin_token

  # GET /admin/chat - Chat UI for testing AI Trainer
  def chat_ui
    render html: chat_html.html_safe, layout: false
  end

  # GET /admin/test_users - List available test users
  def test_users_list
    users = User.where("email LIKE ?", "testuser_%@repstack.test")
                .includes(:user_profile, :workout_sessions)
                .order(:id)
                .limit(100)
    
    render json: {
      count: users.size,
      users: users.map do |u|
        profile = u.user_profile
        sessions = u.workout_sessions
        yesterday = sessions.where(start_time: 1.day.ago.beginning_of_day..1.day.ago.end_of_day).first
        
        {
          id: u.id,
          email: u.email,
          name: u.name,
          level: profile&.numeric_level,
          goal: profile&.fitness_goal,
          total_sessions: sessions.count,
          has_yesterday: yesterday.present?,
          yesterday_focus: yesterday&.name
        }
      end
    }
  end

  # POST /admin/chat - Process chat message
  def chat_send
    message = params[:message].to_s  # Allow empty string for AI-first greeting
    user_type = params[:user_type] || "existing"
    
    # 빈 메시지 허용 (AI 첫 인사/daily greeting 트리거)
    # - 신규 유저: AI 상담 시작
    # - 기존 유저: Daily greeting (어제 운동 요약 + 컨디션 질문)

    level = params[:level]&.to_i || 5
    
    # Support selecting specific test user by ID
    if params[:test_user_id].present?
      user = User.find_by(id: params[:test_user_id])
      return render json: { error: "Test user not found" }, status: :not_found unless user
      token = JsonWebToken.encode(user_id: user.id)
    else
      user, token = get_or_create_test_user(level, user_type: user_type)
    end

    result = ChatService.process(
      user: user,
      message: message,
      routine_id: params[:routine_id],
      session_id: params[:session_id]
    )

    render json: result.merge(jwt_token: token, user_type: user_type, user_id: user.id, user_name: user.name)
  end

  # GET /admin/test_user_info
  def test_user_info
    user_type = params[:user_type] || "existing"
    email = user_type == "new" ? "test_new@repstack.io" : "test@repstack.io"
    user = User.find_by(email: email)

    return render json: { error: "Test user not found", user_type: user_type }, status: :not_found unless user

    token = JsonWebToken.encode(user_id: user.id)

    render json: {
      id: user.id,
      email: user.email,
      user_type: user_type,
      level: user.user_profile&.numeric_level,
      jwt_token: token,
      recent_routines: user.workout_routines.order(created_at: :desc).limit(5).map { |r|
        { id: r.id, created_at: r.created_at, exercises_count: r.routine_exercises.count }
      }
    }
  end

  # POST /admin/reset_test_user
  def reset_test_user
    user_type = params[:user_type] || "existing_with_data"
    email = user_type == "new" ? "test_new@repstack.io" : "test@repstack.io"
    user = User.find_by(email: email)

    return render json: { error: "Test user not found" }, status: :not_found unless user

    # Clear existing data
    user.workout_routines.destroy_all
    user.workout_sessions.destroy_all
    user.training_programs.destroy_all if user.respond_to?(:training_programs)

    new_level = user_type == "new" ? 1 : (params[:level]&.to_i || 5)

    # Update profile with proper onboarding state
    profile_updates = {
      numeric_level: new_level,
      fitness_factors: {}
    }

    case user_type
    when "new"
      # 신규 유저: form만 완료, AI 상담 필요
      profile_updates[:form_onboarding_completed_at] = Time.current
      profile_updates[:onboarding_completed_at] = nil
    when "existing_with_data", "existing_without_data"
      # 기존 유저: 온보딩 완료 상태
      profile_updates[:form_onboarding_completed_at] = Time.current
      profile_updates[:onboarding_completed_at] = Time.current

      # Create TrainingProgram for existing users
      create_test_training_program(user, new_level)

      # Create workout data for existing_with_data
      if user_type == "existing_with_data"
        create_test_workout_data(user, new_level)
      end
    end

    user.user_profile&.update!(profile_updates)

    render json: {
      success: true,
      message: "Test user reset",
      user_type: user_type,
      has_program: user.training_programs.exists?,
      has_workout_data: user.workout_routines.exists?
    }
  end

  # POST /admin/simulate_testflight_feedback - Simulate a TestFlight feedback for testing pipeline
  # POST /admin/poll_testflight - Trigger ASC feedback polling immediately
  def poll_testflight
    unless AppStoreConnectService.configured?
      return render json: { error: "App Store Connect not configured" }, status: :service_unavailable
    end

    new_feedbacks = AppStoreConnectService.fetch_new_feedback
    results = new_feedbacks.map do |data|
      attrs = data.dig("attributes") || {}
      feedback = TestflightFeedback.create!(
        asc_feedback_id: data["id"],
        feedback_text: attrs["comment"] || attrs["feedback"],
        app_version: attrs["appVersionString"],
        build_number: attrs["buildNumber"],
        device_model: attrs["deviceModel"],
        os_version: attrs["osVersion"],
        crash_log: attrs["crashLog"],
        status: "received",
        pipeline_log: [{ event: "received", at: Time.current.iso8601 }]
      )
      TestflightFeedbackAnalysisJob.perform_async(feedback.id)
      { id: feedback.id, asc_id: data["id"], text: (attrs["comment"] || attrs["feedback"]).to_s.truncate(80) }
    rescue ActiveRecord::RecordNotUnique
      { asc_id: data["id"], skipped: "duplicate" }
    end

    render json: {
      polled_at: Time.current.iso8601,
      new_feedback_count: new_feedbacks.size,
      results: results
    }
  rescue StandardError => e
    render json: { error: e.message }, status: :internal_server_error
  end

  def simulate_testflight_feedback
    feedback = TestflightFeedback.create!(
      asc_feedback_id: "sim_#{SecureRandom.hex(8)}",
      feedback_text: params[:feedback_text] || "앱이 크래시됩니다",
      app_version: params[:app_version] || "1.0.0",
      build_number: params[:build_number] || "42",
      device_model: params[:device_model] || "iPhone 15 Pro",
      os_version: params[:os_version] || "iOS 18.0",
      crash_log: params[:crash_log],
      status: "received",
      pipeline_log: [{ event: "simulated", at: Time.current.iso8601 }]
    )

    # Trigger analysis pipeline (sync mode for testing, async for production)
    if params[:sync] == "true"
      TestflightFeedbackAnalysisJob.new.perform(feedback.id)
      feedback.reload
    else
      TestflightFeedbackAnalysisJob.perform_async(feedback.id)
    end

    render json: {
      id: feedback.id,
      status: feedback.status,
      bug_category: feedback.bug_category,
      severity: feedback.severity,
      affected_repo: feedback.affected_repo,
      auto_fixable: feedback.auto_fixable?,
      github_issue_url: feedback.github_issue_url,
      message: params[:sync] == "true" ? "Pipeline executed synchronously." : "Analysis job enqueued.",
      check_status: "/admin/testflight_feedback_status?id=#{feedback.id}"
    }
  end

  # GET /admin/testflight_feedback_status - Check pipeline status for a feedback
  def testflight_feedback_status
    feedback = TestflightFeedback.find_by(id: params[:id])
    return render json: { error: "Not found" }, status: :not_found unless feedback

    render json: {
      id: feedback.id,
      status: feedback.status,
      bug_category: feedback.bug_category,
      severity: feedback.severity,
      affected_repo: feedback.affected_repo,
      auto_fixable: feedback.auto_fixable?,
      ai_analysis_json: feedback.ai_analysis_json,
      github_issue_url: feedback.github_issue_url,
      github_pr_url: feedback.github_pr_url,
      pipeline_log: feedback.pipeline_log,
      created_at: feedback.created_at,
      updated_at: feedback.updated_at
    }
  end

  # GET /admin/testflight_feedbacks - List all feedbacks with filtering
  def testflight_feedbacks_list
    feedbacks = TestflightFeedback.order(created_at: :desc)
    feedbacks = feedbacks.where(status: params[:status]) if params[:status].present?
    feedbacks = feedbacks.where(severity: params[:severity]) if params[:severity].present?
    feedbacks = feedbacks.limit(params[:limit]&.to_i || 50)

    render json: {
      count: feedbacks.size,
      feedbacks: feedbacks.map { |f|
        {
          id: f.id,
          status: f.status,
          bug_category: f.bug_category,
          severity: f.severity,
          affected_repo: f.affected_repo,
          feedback_text: f.feedback_text&.truncate(100),
          github_issue_url: f.github_issue_url,
          created_at: f.created_at
        }
      }
    }
  end

  # DELETE /admin/delete_user_data - Delete all data for a user by email
  def delete_user_data
    email = params[:email]
    return render json: { error: "Email required" }, status: :bad_request unless email.present?

    user = User.find_by(email: email)
    return render json: { error: "User not found: #{email}" }, status: :not_found unless user

    deleted_counts = {}

    # Delete related data (order matters due to FK constraints)
    deleted_counts[:onboarding_analytics] = OnboardingAnalytics.where(user_id: user.id).delete_all
    deleted_counts[:chat_messages] = ChatMessage.where(user_id: user.id).delete_all
    deleted_counts[:condition_logs] = user.condition_logs.delete_all if user.respond_to?(:condition_logs)
    deleted_counts[:workout_feedbacks] = user.workout_feedbacks.delete_all if user.respond_to?(:workout_feedbacks)
    deleted_counts[:workout_records] = user.workout_records.delete_all if user.respond_to?(:workout_records)
    deleted_counts[:level_test_verifications] = user.level_test_verifications.delete_all if user.respond_to?(:level_test_verifications)
    deleted_counts[:fitness_test_submissions] = user.fitness_test_submissions.delete_all if user.respond_to?(:fitness_test_submissions)
    deleted_counts[:workout_sets] = WorkoutSet.joins(:workout_session).where(workout_sessions: { user_id: user.id }).delete_all
    deleted_counts[:routine_exercises] = RoutineExercise.joins(:workout_routine).where(workout_routines: { user_id: user.id }).delete_all
    deleted_counts[:workout_sessions] = user.workout_sessions.delete_all
    deleted_counts[:workout_routines] = user.workout_routines.delete_all
    deleted_counts[:training_programs] = user.training_programs.delete_all if user.respond_to?(:training_programs)
    deleted_counts[:user_profile] = user.user_profile&.destroy ? 1 : 0
    deleted_counts[:user] = user.destroy ? 1 : 0

    render json: {
      success: true,
      message: "User and all related data deleted",
      email: email,
      deleted_counts: deleted_counts
    }
  rescue StandardError => e
    render json: { error: e.message }, status: :internal_server_error
  end

  def create_test_training_program(user, level)
    # Determine periodization based on level
    periodization = level <= 3 ? "linear" : "undulating"
    total_weeks = level <= 3 ? 8 : 12

    TrainingProgram.create!(
      user: user,
      name: "#{total_weeks}주 근비대 프로그램",
      status: "active",
      total_weeks: total_weeks,
      current_week: rand(1..4),
      goal: "근비대",
      periodization_type: periodization,
      weekly_plan: {
        "1-3" => { "phase" => "적응기", "volume_modifier" => 0.8 },
        "4-8" => { "phase" => "성장기", "volume_modifier" => 1.0 },
        "9-11" => { "phase" => "강화기", "volume_modifier" => 1.1 },
        "12" => { "phase" => "디로드", "volume_modifier" => 0.6 }
      },
      split_schedule: {
        "1" => { "focus" => "가슴/삼두", "muscles" => ["chest", "triceps"] },
        "2" => { "focus" => "등/이두", "muscles" => ["back", "biceps"] },
        "3" => { "focus" => "하체", "muscles" => ["legs", "glutes"] },
        "4" => { "focus" => "어깨/복근", "muscles" => ["shoulders", "core"] },
        "5" => { "focus" => "휴식", "muscles" => [] },
        "6" => { "focus" => "상체", "muscles" => ["chest", "back", "shoulders"] },
        "7" => { "focus" => "휴식", "muscles" => [] }
      },
      started_at: (rand(1..3)).weeks.ago
    )
  end

  def create_test_workout_data(user, level)
    exercises_pool = [
      { name: "벤치프레스", muscle: "chest", weight: 60 },
      { name: "인클라인 덤벨프레스", muscle: "chest", weight: 20 },
      { name: "케이블 크로스오버", muscle: "chest", weight: 15 },
      { name: "렛풀다운", muscle: "back", weight: 50 },
      { name: "바벨로우", muscle: "back", weight: 50 },
      { name: "덤벨 숄더프레스", muscle: "shoulders", weight: 16 },
      { name: "레터럴레이즈", muscle: "shoulders", weight: 8 },
      { name: "스쿼트", muscle: "legs", weight: 80 },
      { name: "레그프레스", muscle: "legs", weight: 120 },
      { name: "바벨컬", muscle: "biceps", weight: 25 },
      { name: "트라이셉 푸시다운", muscle: "triceps", weight: 20 }
    ]

    # Create past routines AND workout sessions
    [1, 2, 4].each do |days_ago|
      target_date = Date.current - days_ago.days
      workout_types = ["upper", "lower", "push", "pull"]

      # Create WorkoutRoutine (AI plan)
      routine = WorkoutRoutine.create!(
        user: user,
        level: user.user_profile&.tier || "intermediate",
        week_number: 2,
        day_number: target_date.cwday,
        workout_type: workout_types.sample,
        day_of_week: target_date.strftime("%A"),
        estimated_duration: [45, 60, 75].sample,
        is_completed: true,
        completed_at: (days_ago.days.ago + 1.hour),
        generated_at: days_ago.days.ago,
        created_at: days_ago.days.ago
      )

      # Add exercises to routine
      selected = exercises_pool.sample(rand(4..6))
      selected.each_with_index do |ex, idx|
        RoutineExercise.create!(
          workout_routine: routine,
          exercise_name: ex[:name],
          target_muscle: ex[:muscle],
          sets: rand(3..4),
          reps: rand(8..12),
          order_index: idx
        )
      end

      # Create WorkoutSession (actual workout record)
      session_start = days_ago.days.ago.change(hour: 18, min: 0)
      session_end = session_start + rand(45..75).minutes

      session = WorkoutSession.create!(
        user: user,
        name: routine.day_of_week + " 운동",
        start_time: session_start,
        end_time: session_end,
        notes: "테스트 운동 세션",
        created_at: session_start
      )

      # Add workout sets to session
      selected.each do |ex|
        sets_count = rand(3..4)
        sets_count.times do
          WorkoutSet.create!(
            workout_session: session,
            exercise_name: ex[:name],
            weight: ex[:weight] + rand(-5..10),
            reps: rand(8..12),
            created_at: session_start + rand(5..50).minutes
          )
        end
      end
    end

    # Create workout feedback
    if user.respond_to?(:workout_feedbacks)
      WorkoutFeedback.create!(
        user: user,
        feedback_type: ["just_right", "too_easy", "too_hard"].sample,
        feedback_text: "적당했어요",
        recorded_at: 1.day.ago
      ) rescue nil
    end
  end

  # POST /admin/random_form_complete - Set random form completion state for testing AI consultation
  def random_form_complete
    user_type = params[:user_type] || "existing"
    email = user_type == "new" ? "test_new@repstack.io" : "test@repstack.io"
    user = User.find_by(email: email)

    return render json: { error: "Test user not found" }, status: :not_found unless user

    # Clear existing data
    user.workout_routines.destroy_all
    user.workout_sessions.destroy_all

    # Random values
    experience_levels = %w[beginner intermediate advanced]
    fitness_goals = ["근비대", "다이어트", "체력 향상", "건강 유지"]

    random_experience = experience_levels.sample
    random_goal = fitness_goals.sample
    random_height = rand(155..190)
    random_weight = rand(50..95)

    # Set numeric level based on experience
    numeric_level = case random_experience
      when "beginner" then rand(1..2)
      when "intermediate" then rand(3..5)
      when "advanced" then rand(6..8)
      else 1
    end

    # Update profile - form completed but AI consultation NOT completed
    profile = user.user_profile || user.create_user_profile!
    profile.update!(
      current_level: random_experience,
      numeric_level: numeric_level,
      fitness_goal: random_goal,
      height: random_height,
      weight: random_weight,
      form_onboarding_completed_at: Time.current,
      onboarding_completed_at: nil,  # AI consultation not done yet
      fitness_factors: {}  # Clear any previous assessment state
    )

    # Generate AI greeting (AI starts the conversation)
    ai_result = AiTrainer::LevelAssessmentService.assess(user: user, message: "")
    ai_greeting = ai_result[:success] ? ai_result[:message] : "안녕하세요! 맞춤 운동 프로그램을 만들어드릴게요. 💪"

    render json: {
      success: true,
      message: "Random form complete state set",
      user_type: user_type,
      profile: {
        experience_level: random_experience,
        numeric_level: numeric_level,
        fitness_goal: random_goal,
        height: random_height,
        weight: random_weight
      },
      ai_greeting: ai_greeting
    }
  end

  # POST /admin/delete_test_routines
  def delete_test_routines
    user_type = params[:user_type] || "existing"
    email = user_type == "new" ? "test_new@repstack.io" : "test@repstack.io"
    user = User.find_by(email: email)

    return render json: { error: "Test user not found" }, status: :not_found unless user

    count = user.workout_routines.count
    user.workout_routines.destroy_all

    render json: { success: true, deleted: count, user_type: user_type }
  end

  # POST /admin/normalize_exercises
  # mode=preview (기본) / mode=execute (실행)
  # 1. 영어 이름 → 한글 변환
  # 2. 중복 운동 제거 (한글 이름 기준)
  def normalize_exercises
    mode = params[:mode] || "preview"

    results = {
      mode: mode,
      step1_conversions: [],
      step2_duplicates: [],
      summary: {}
    }

    # Step 1: 영어 → 한글 변환
    Exercise.find_each do |exercise|
      current_name = exercise.display_name || exercise.name
      korean_name = AiTrainer::ExerciseNameNormalizer.normalize(current_name)

      next unless korean_name != current_name && AiTrainer::ExerciseNameNormalizer.korean?(korean_name)

      if mode == "execute"
        exercise.update!(display_name: korean_name)
      end
      results[:step1_conversions] << { id: exercise.id, from: current_name, to: korean_name }
    end

    # Step 2: 중복 제거 (display_name 기준)
    duplicates = Exercise.group(:display_name)
                         .having("COUNT(*) > 1")
                         .count

    duplicates.each do |name, count|
      next if name.blank?

      exercises = Exercise.where(display_name: name).order(:id)
      keep = exercises.first
      to_delete = exercises.offset(1)

      to_delete.each do |dup|
        results[:step2_duplicates] << {
          keep_id: keep.id,
          delete_id: dup.id,
          name: name
        }

        if mode == "execute"
          # 참조 업데이트: routine_exercises의 exercise_name을 유지 (이미 문자열이므로 OK)
          # workout_sets도 exercise_name 문자열 사용
          dup.destroy
        end
      end
    end

    results[:summary] = {
      conversions: results[:step1_conversions].count,
      duplicates_removed: results[:step2_duplicates].count
    }

    render json: results
  end

  # GET /admin/exercise_stats
  def exercise_stats
    total = Exercise.count
    english_exercises = Exercise.all.reject { |e| (e.display_name || e.name).to_s.match?(/[가-힣]/) }
    korean_count = total - english_exercises.count

    render json: {
      total: total,
      korean: korean_count,
      english: english_exercises.count,
      korean_percent: (korean_count.to_f / total * 100).round(1),
      english_list: english_exercises.map { |e| { id: e.id, name: e.display_name || e.name } }
    }
  end

  # GET /admin/exercise_data_status
  # 운동 데이터 필드 채움 현황
  def exercise_data_status
    total = Exercise.count

    fields = {
      description: Exercise.where.not(description: [nil, ""]).count,
      form_tips: Exercise.where.not(form_tips: [nil, ""]).count,
      common_mistakes: Exercise.where.not(common_mistakes: [nil, ""]).count,
      equipment: Exercise.where("array_length(equipment, 1) > 0").count,
      secondary_muscles: Exercise.where("array_length(secondary_muscles, 1) > 0").count,
      video_references: Exercise.where("jsonb_array_length(video_references) > 0").count,
      variations: Exercise.where("variations != '{}'::jsonb").count
    }

    field_stats = fields.map do |name, count|
      { field: name.to_s, count: count, percent: (count.to_f / total * 100).round(1) }
    end

    # 샘플 데이터 (설명 있는 운동 3개)
    samples = Exercise.where.not(description: [nil, ""]).limit(3).map do |e|
      {
        name: e.display_name || e.name,
        description: e.description&.truncate(200),
        form_tips: e.form_tips&.truncate(100),
        equipment: e.equipment,
        video_count: e.video_references&.size || 0
      }
    end

    # 비디오 없는 운동 샘플
    no_video_samples = Exercise.where("jsonb_array_length(video_references) = 0 OR video_references IS NULL")
                               .limit(10)
                               .pluck(:display_name)

    # Knowledge Chunks 현황
    chunk_stats = {
      total_chunks: FitnessKnowledgeChunk.count,
      chunks_with_exercise: FitnessKnowledgeChunk.where.not(exercise_name: [nil, ""]).count,
      unique_exercises_in_chunks: FitnessKnowledgeChunk.where.not(exercise_name: [nil, ""]).distinct.pluck(:exercise_name).count,
      by_knowledge_type: FitnessKnowledgeChunk.group(:knowledge_type).count
    }

    # YouTube Videos 현황
    video_stats = {
      total_videos: YoutubeVideo.count,
      analyzed: YoutubeVideo.where(analysis_status: "completed").count,
      pending: YoutubeVideo.where(analysis_status: "pending").count,
      with_transcript: YoutubeVideo.where.not(transcript: [nil, ""]).count
    }

    # Chunk에 있는 운동 vs Exercise 테이블 매칭
    chunk_exercise_names = FitnessKnowledgeChunk.where.not(exercise_name: [nil, ""]).distinct.pluck(:exercise_name)
    exercise_names = Exercise.pluck(:display_name, :name, :english_name).flatten.compact.map(&:downcase)

    matched = chunk_exercise_names.select { |name| exercise_names.include?(name.downcase) }
    unmatched = chunk_exercise_names.reject { |name| exercise_names.include?(name.downcase) }

    # Chunk exercise_name 샘플 (다양한 유형)
    chunk_samples = FitnessKnowledgeChunk
      .where.not(exercise_name: [nil, ""])
      .order("RANDOM()")
      .limit(30)
      .pluck(:exercise_name, :knowledge_type, :summary)
      .map { |name, type, summary| { exercise_name: name, type: type, summary: summary&.truncate(100) } }

    render json: {
      exercise_table: {
        total: total,
        field_stats: field_stats
      },
      knowledge_chunks: chunk_stats,
      youtube_videos: video_stats,
      chunk_exercise_matching: {
        total_in_chunks: chunk_exercise_names.count,
        matched_with_exercise_table: matched.count,
        unmatched: unmatched.count,
        unmatched_samples: unmatched.first(20)
      },
      chunk_samples: chunk_samples
    }
  end

  # POST /admin/deactivate_suspicious_exercises
  # 분석 결과 의심 항목 비활성화 (예외 항목 제외)
  def deactivate_suspicious_exercises
    # 유지할 운동들
    keep_names = [
      "1RM 테스트",
      "싱글레그 브릿지 테스트",
      "파버 테스트",
      "포즈 스쿼트"
    ]

    # 비활성화할 패턴들
    non_exercise_patterns = [
      /해부학|anatomy/i, /생리학|physiology/i, /테스트|test|평가|assessment/i,
      /진단|diagnosis/i, /분석|analysis/i, /모니터링|monitoring/i, /추적|tracking/i,
      /식사|meal|breakfast|lunch|dinner/i, /영양|nutrition|섭취|intake/i,
      /레시피|recipe/i, /요리|cooking/i, /칼로리|calori/i,
      /스테로이드|steroid/i, /주사|injection/i, /사이클|cycle/i, /부작용|side effect/i,
      /트렌볼론|trenbolone/i, /아나드롤|anadrol/i, /디아나볼|dianabol/i,
      /클렌부테롤|clenbuterol/i, /난드롤론|nandrolone/i, /sarm|rad.?140/i, /finasteride|minoxidil/i,
      /수면|sleep|nap/i, /스트레스|stress/i, /습관|habit/i, /동기|motivation/i,
      /마인드|mind|mental/i, /목표 설정|goal setting/i, /라이프스타일|lifestyle/i,
      /콘텐츠|content/i, /코칭|coaching/i, /온라인|online/i, /제품|product/i,
      /전략|strategy/i, /방법론|methodology/i, /단계|phase/i, /주기화|periodization/i,
      /유지|maintenance/i, /적응|adaptation/i, /포즈|pose/i, /프레젠테이션|presentation/i,
      /복싱|boxing/i, /주짓수|jiu.?jitsu/i, /레슬링|wrestling/i, /서핑|surfing/i,
      /수영|swimming/i, /야구|baseball/i, /격투|combat/i, /사이클링|cycling/i
    ]

    exercises = Exercise.where(active: true)
    to_deactivate = []

    exercises.each do |ex|
      name = ex.display_name || ex.name

      # 유지할 운동은 스킵
      next if keep_names.any? { |keep| name.include?(keep) }

      # 패턴 매칭되면 비활성화 대상
      if non_exercise_patterns.any? { |pattern| name.match?(pattern) }
        to_deactivate << ex
      end
    end

    # 비활성화 실행
    deactivated_names = to_deactivate.map { |ex| ex.display_name || ex.name }
    Exercise.where(id: to_deactivate.map(&:id)).update_all(active: false)

    remaining = Exercise.where(active: true).count

    render json: {
      deactivated_count: to_deactivate.count,
      deactivated_names: deactivated_names,
      remaining_active: remaining,
      kept: keep_names
    }
  end

  # GET /admin/analyze_exercises
  # 활성 운동 분석 - 루틴에 부적합한 항목 찾기
  def analyze_exercises
    exercises = Exercise.where(active: true).order(:display_name)

    # 운동이 아닌 것 같은 패턴들
    non_exercise_patterns = [
      # 개념/이론
      /해부학|anatomy/i,
      /생리학|physiology/i,
      /테스트|test|평가|assessment/i,
      /진단|diagnosis/i,
      /분석|analysis/i,
      /모니터링|monitoring/i,
      /추적|tracking/i,

      # 영양/식단
      /식사|meal|breakfast|lunch|dinner/i,
      /영양|nutrition|섭취|intake/i,
      /레시피|recipe/i,
      /요리|cooking/i,
      /칼로리|calori/i,
      /단백질|protein/i,
      /탄수화물|carb/i,

      # 약물/보충제
      /스테로이드|steroid/i,
      /주사|injection/i,
      /사이클|cycle/i,
      /부작용|side effect/i,
      /트렌볼론|trenbolone/i,
      /아나드롤|anadrol/i,
      /디아나볼|dianabol/i,
      /클렌부테롤|clenbuterol/i,
      /난드롤론|nandrolone/i,
      /테스토스테론|testosterone/i,
      /sarm|rad.?140/i,
      /finasteride|minoxidil/i,

      # 라이프스타일
      /수면|sleep|nap/i,
      /스트레스|stress/i,
      /습관|habit/i,
      /동기|motivation/i,
      /마인드|mind|mental/i,
      /목표 설정|goal setting/i,
      /라이프스타일|lifestyle/i,

      # 비즈니스/콘텐츠
      /콘텐츠|content/i,
      /코칭|coaching/i,
      /온라인|online/i,
      /제품|product/i,
      /평가|evaluation/i,

      # 일반 개념
      /전략|strategy/i,
      /방법론|methodology/i,
      /원칙|principle/i,
      /진행|progression(?! 운동)/i,
      /단계|phase/i,
      /주기화|periodization/i,
      /유지|maintenance/i,
      /적응|adaptation/i,

      # 포즈 (보디빌딩)
      /포즈|pose/i,
      /프레젠테이션|presentation/i,

      # 스포츠 (웨이트가 아닌)
      /복싱|boxing/i,
      /주짓수|jiu.?jitsu/i,
      /레슬링|wrestling/i,
      /서핑|surfing/i,
      /수영|swimming/i,
      /야구|baseball/i,
      /격투|combat/i
    ]

    suspicious = []
    valid = []

    exercises.each do |ex|
      name = ex.display_name || ex.name
      is_suspicious = non_exercise_patterns.any? { |pattern| name.match?(pattern) }

      if is_suspicious
        suspicious << {
          id: ex.id,
          name: name,
          muscle_group: ex.muscle_group,
          video_count: ex.video_references&.size || 0,
          description: ex.description&.truncate(100)
        }
      else
        valid << { id: ex.id, name: name }
      end
    end

    render json: {
      total_active: exercises.count,
      suspicious_count: suspicious.count,
      valid_count: valid.count,
      suspicious_exercises: suspicious,
      valid_sample: valid.first(30)
    }
  end

  # POST /admin/deactivate_exercises_without_video
  # 영상 없는 운동 비활성화
  # ?dry_run=true (기본) - 미리보기만
  # ?dry_run=false - 실제 실행
  def deactivate_exercises_without_video
    dry_run = params[:dry_run] != "false"

    # 영상 없는 운동 찾기
    exercises_without_video = Exercise.where(
      "video_references = '[]'::jsonb OR video_references IS NULL OR jsonb_array_length(video_references) = 0"
    ).where(active: true)

    count = exercises_without_video.count
    samples = exercises_without_video.limit(20).pluck(:id, :display_name)

    if !dry_run && count > 0
      exercises_without_video.update_all(active: false)
    end

    # 남은 활성 운동 통계
    active_count = Exercise.where(active: true).count
    active_with_video = Exercise.where(active: true)
      .where("jsonb_array_length(video_references) > 0").count

    render json: {
      dry_run: dry_run,
      deactivated_count: dry_run ? 0 : count,
      would_deactivate: count,
      samples: samples.map { |id, name| { id: id, name: name } },
      after_stats: {
        total_active: dry_run ? active_count : (active_count - count),
        with_video: active_with_video
      }
    }
  end

  # POST /admin/test_routine_generator
  # ToolBasedRoutineGenerator 직접 테스트
  def test_routine_generator
    user_type = params[:user_type] || "existing"
    level = params[:level]&.to_i || 5
    goal = params[:goal] || "가슴 운동"

    user, _token = get_or_create_test_user(level, user_type: user_type)

    generator = AiTrainer::ToolBasedRoutineGenerator.new(user: user)
    generator.with_goal(goal)

    result = generator.generate

    # 운동별 데이터 상세 확인
    exercise_details = result[:exercises]&.map do |ex|
      {
        name: ex[:exercise_name],
        has_description: ex[:description].present?,
        has_instructions: ex[:instructions].present?,
        video_count: ex[:video_references]&.size || 0,
        video_urls: ex[:video_references]&.map { |v| v[:url] }
      }
    end

    render json: {
      success: result[:exercises].present?,
      routine_name: result[:fitness_factor_korean],
      exercise_count: result[:exercises]&.size || 0,
      exercises_with_video: result[:exercises]&.count { |e| e[:video_references]&.any? } || 0,
      exercises_with_description: result[:exercises]&.count { |e| e[:description].present? } || 0,
      exercise_details: exercise_details,
      full_routine: result
    }
  end

  # POST /admin/sync_exercise_knowledge
  # Chunk 데이터를 Exercise 테이블에 동기화
  # ?dry_run=true (기본) - 미리보기만
  # ?dry_run=false - 실제 실행
  def sync_exercise_knowledge
    dry_run = params[:dry_run] != "false"

    service = ExerciseKnowledgeSyncService.new(dry_run: dry_run)
    stats = service.sync_all

    # 동기화 후 Exercise 데이터 현황
    exercise_stats = {
      total: Exercise.count,
      with_description: Exercise.where.not(description: [nil, ""]).count,
      with_form_tips: Exercise.where.not(form_tips: [nil, ""]).count,
      with_video_refs: Exercise.where("jsonb_array_length(video_references) > 0").count
    }

    render json: {
      dry_run: dry_run,
      sync_stats: stats,
      exercise_stats_after: exercise_stats
    }
  end

  # POST /admin/reanalyze_videos
  # Triggers reanalysis of all videos with timestamp extraction
  # Use ?status=pending|completed|all (default: all)
  def reanalyze_videos
    status = params[:status] || "all"

    videos = case status
    when "pending" then YoutubeVideo.pending
    when "completed" then YoutubeVideo.completed
    else YoutubeVideo.all
    end

    total = videos.count

    videos.find_each do |video|
      ReanalyzeVideoJob.perform_async(video.id)
    end

    render json: {
      success: true,
      message: "Enqueued #{total} videos for reanalysis",
      estimated_hours: (total * 17.0 / 5 / 3600).round(1),
      status_filter: status
    }
  end

  # POST /admin/stop_reanalysis
  # Stop all pending reanalysis jobs
  def stop_reanalysis
    require "sidekiq/api"

    # Clear all analysis-related queues
    cleared_count = 0
    %w[youtube_analysis video_analysis default].each do |queue_name|
      queue = Sidekiq::Queue.new(queue_name)
      cleared_count += queue.size
      queue.clear
    end

    # Also clear any scheduled jobs for ReanalyzeVideoJob
    scheduled = Sidekiq::ScheduledSet.new
    scheduled_cleared = scheduled.select { |job| job.klass == "ReanalyzeVideoJob" }.each(&:delete).count

    # Clear retry set for failed jobs
    retry_set = Sidekiq::RetrySet.new
    retry_cleared = retry_set.size
    retry_set.clear

    # Reset analyzing videos back to completed
    analyzing_reset = YoutubeVideo.analyzing.update_all(analysis_status: "completed")

    render json: {
      success: true,
      message: "All jobs stopped",
      cleared_queued_jobs: cleared_count,
      cleared_scheduled_jobs: scheduled_cleared,
      cleared_retry_jobs: retry_cleared,
      reset_analyzing_videos: analyzing_reset
    }
  end

  # GET /admin/worker_status
  # Check Sidekiq worker status
  def worker_status
    require "sidekiq/api"

    stats = Sidekiq::Stats.new
    processes = Sidekiq::ProcessSet.new

    # Get queue sizes
    queues = Sidekiq::Queue.all.map do |q|
      { name: q.name, size: q.size }
    end

    # Get currently processing jobs
    workers = Sidekiq::Workers.new
    current_jobs = workers.map do |process_id, thread_id, work|
      {
        queue: work["queue"],
        class: work["payload"]["class"],
        args: work["payload"]["args"]&.first(2),
        started_at: Time.at(work["run_at"]).iso8601
      }
    end

    render json: {
      processed: stats.processed,
      failed: stats.failed,
      queues: queues,
      workers_count: workers.size,
      current_jobs: current_jobs.first(5)
    }
  end

  # POST /admin/stop_transcript_extraction
  # Stop transcript extraction jobs
  def stop_transcript_extraction
    require "sidekiq/api"

    # Clear the low queue (where ExtractTranscriptsJob runs)
    queue = Sidekiq::Queue.new("low")
    cleared_count = queue.size
    queue.clear

    # Clear scheduled ExtractTranscriptsJob
    scheduled = Sidekiq::ScheduledSet.new
    scheduled_cleared = scheduled.select { |job| job.klass == "ExtractTranscriptsJob" }.each(&:delete).count

    render json: {
      success: true,
      message: "Transcript extraction stopped",
      cleared_queued_jobs: cleared_count,
      cleared_scheduled_jobs: scheduled_cleared
    }
  end

  # POST /admin/seed_channels
  # Seed all configured YouTube channels
  def seed_channels
    YoutubeChannel.seed_configured_channels!

    channels = YoutubeChannel.all.map do |c|
      { name: c.name, handle: c.handle, language: c.language }
    end

    render json: {
      success: true,
      channels: channels,
      total: channels.count
    }
  end

  # POST /admin/toggle_channel
  # Toggle channel active status
  # Params: handle (required), active (optional, defaults to toggle)
  def toggle_channel
    handle = params[:handle]
    return render json: { error: "handle parameter required" }, status: :bad_request unless handle.present?

    channel = YoutubeChannel.find_by(handle: handle)
    return render json: { error: "Channel not found: #{handle}" }, status: :not_found unless channel

    # If active param is specified, use it; otherwise toggle
    new_active = if params[:active].present?
      ActiveModel::Type::Boolean.new.cast(params[:active])
    else
      !channel.active
    end

    channel.update!(active: new_active)

    render json: {
      success: true,
      channel: channel.name,
      handle: channel.handle,
      active: channel.active
    }
  end

  # POST /admin/bulk_import_videos
  # Import videos from yt-dlp extracted data
  # Body: { channel_handle: "jeffnippard", videos: [{ video_id: "xxx", title: "...", upload_date: "2024-01-01" }] }
  def bulk_import_videos
    channel_handle = params[:channel_handle]
    videos_data = params[:videos]

    channel = YoutubeChannel.find_by(handle: channel_handle)
    unless channel
      return render json: { error: "Channel not found: #{channel_handle}" }, status: :not_found
    end

    imported = 0
    skipped = 0

    videos_data.each do |video|
      existing = channel.youtube_videos.find_by(video_id: video[:video_id])
      if existing
        skipped += 1
        next
      end

      channel.youtube_videos.create!(
        video_id: video[:video_id],
        title: video[:title] || "Untitled",
        published_at: video[:upload_date],
        analysis_status: "pending"
      )
      imported += 1
    rescue StandardError => e
      Rails.logger.warn("Failed to import video #{video[:video_id]}: #{e.message}")
    end

    channel.mark_synced!

    render json: {
      success: true,
      channel: channel.name,
      imported: imported,
      skipped: skipped,
      total_videos: channel.youtube_videos.count
    }
  end

  # GET /admin/sample_knowledge
  # Get random samples of knowledge data for review
  def sample_knowledge
    knowledge_type = params[:type] || "all"
    limit = [params[:limit]&.to_i || 30, 100].min

    scope = if knowledge_type == "all"
              FitnessKnowledgeChunk.all
            else
              FitnessKnowledgeChunk.where(knowledge_type: knowledge_type)
            end

    samples = scope.order("RANDOM()").limit(limit).map do |chunk|
      {
        id: chunk.id,
        type: chunk.knowledge_type,
        exercise_name: chunk.exercise_name,
        muscle_group: chunk.muscle_group,
        summary: chunk.summary&.truncate(200),
        content: chunk.content&.truncate(300)
      }
    end

    render json: {
      total_count: scope.count,
      sample_count: samples.size,
      samples: samples
    }
  end

  # GET /admin/list_knowledge
  # List all knowledge with pagination for export
  def list_knowledge
    knowledge_type = params[:type] || "all"
    page = [params[:page]&.to_i || 1, 1].max
    per_page = [params[:per_page]&.to_i || 100, 500].min

    scope = if knowledge_type == "all"
              FitnessKnowledgeChunk.all
            else
              FitnessKnowledgeChunk.where(knowledge_type: knowledge_type)
            end

    total_count = scope.count
    total_pages = (total_count.to_f / per_page).ceil

    chunks = scope.order(id: :desc).offset((page - 1) * per_page).limit(per_page).map do |chunk|
      {
        id: chunk.id,
        type: chunk.knowledge_type,
        difficulty: chunk.difficulty_level,
        exercise_name: chunk.exercise_name,
        muscle_group: chunk.muscle_group,
        summary: chunk.summary,
        content: chunk.content,
        video_title: chunk.youtube_video&.title,
        created_at: chunk.created_at&.iso8601
      }
    end

    render json: {
      data: chunks,
      pagination: {
        page: page,
        per_page: per_page,
        total_count: total_count,
        total_pages: total_pages
      }
    }
  end

  # POST /admin/ai_cleanup_knowledge
  # AI-powered cleanup of irrelevant knowledge data
  # Use ?limit=100 (default) and ?dry_run=true to preview
  def ai_cleanup_knowledge
    limit = [params[:limit]&.to_i || 100, 500].min
    dry_run = params[:dry_run] == "true"

    results = KnowledgeCleanupService.cleanup(limit: limit, dry_run: dry_run)

    render json: {
      success: true,
      dry_run: dry_run,
      results: results,
      remaining: FitnessKnowledgeChunk.count
    }
  end

  # DELETE /admin/delete_chunks
  # Delete specific knowledge chunks by IDs
  def delete_chunks
    ids = params[:ids]&.split(",")&.map(&:to_i)
    return render json: { error: "No IDs provided" }, status: :bad_request if ids.blank?

    deleted = FitnessKnowledgeChunk.where(id: ids).destroy_all
    render json: {
      success: true,
      deleted_count: deleted.size,
      deleted_ids: deleted.map(&:id),
      remaining: FitnessKnowledgeChunk.count
    }
  end

  # GET /admin/simulate_beginner
  # Simulate beginner searching for exercises to test knowledge matching
  def simulate_beginner
    exercises = params[:exercises]&.split(",") || nil
    samples = [params[:samples]&.to_i || 5, 10].min

    results = if exercises
                KnowledgeMatchSimulator.run(exercises: exercises, samples_per_exercise: samples)
              else
                KnowledgeMatchSimulator.run(samples_per_exercise: samples)
              end

    render json: {
      success: true,
      simulation: "beginner_exercise_search",
      results: results
    }
  end

  # GET /admin/simulate_all_levels
  # Simulate beginner, intermediate, advanced users in parallel
  def simulate_all_levels
    samples = [params[:samples]&.to_i || 3, 5].min

    results = KnowledgeMatchSimulator.run_all_levels(samples_per_exercise: samples)

    render json: {
      success: true,
      simulation: "all_levels_exercise_search",
      results: results
    }
  end

  # POST /admin/tag_knowledge_levels
  # Tag knowledge chunks with difficulty levels using AI
  def tag_knowledge_levels
    limit = [params[:limit]&.to_i || 100, 500].min

    results = KnowledgeLevelTagger.tag(limit: limit)

    render json: {
      success: true,
      results: results,
      stats: {
        total: FitnessKnowledgeChunk.count,
        beginner: FitnessKnowledgeChunk.where(difficulty_level: "beginner").count,
        intermediate: FitnessKnowledgeChunk.where(difficulty_level: "intermediate").count,
        advanced: FitnessKnowledgeChunk.where(difficulty_level: "advanced").count,
        all: FitnessKnowledgeChunk.where(difficulty_level: "all").count,
        untagged: FitnessKnowledgeChunk.where(difficulty_level: [nil, ""]).count
      }
    }
  end

  # GET /admin/test_subtitle_extraction
  # Test subtitle extraction with timestamps for debugging
  def test_subtitle_extraction
    url = params[:url]
    language = params[:language] || "ko"
    return render json: { error: "url parameter required" }, status: :bad_request unless url

    # Extract subtitles
    transcript = YoutubeChannelScraper.extract_subtitles(url, language: language)

    if transcript.blank?
      return render json: { error: "No subtitles found", url: url, language: language }
    end

    # Show first 2000 chars of transcript to verify timestamps
    render json: {
      success: true,
      url: url,
      transcript_length: transcript.length,
      transcript_preview: transcript[0..2000],
      has_timestamps: transcript.include?("["),
      sample_timestamps: transcript.scan(/\[\d{2}:\d{2}\]/).first(10)
    }
  end

  # POST /admin/test_knowledge_extraction
  # Test full knowledge extraction on a video URL (extracts transcript + analyzes with Claude)
  def test_knowledge_extraction
    url = params[:url]
    return render json: { error: "url parameter required" }, status: :bad_request unless url

    unless YoutubeKnowledgeExtractionService.configured?
      return render json: { error: "ANTHROPIC_API_KEY not configured" }, status: :unprocessable_entity
    end

    # Step 1: Extract transcript
    transcript = YoutubeChannelScraper.extract_subtitles(url)

    if transcript.blank?
      return render json: { error: "No subtitles found", url: url }
    end

    # Step 2: Analyze with Claude
    result = YoutubeKnowledgeExtractionService.analyze_transcript(transcript)

    # Check timestamps in result
    chunks_with_ts = result[:knowledge_chunks]&.select { |c| c[:timestamp_start].present? } || []

    render json: {
      success: true,
      url: url,
      transcript_length: transcript.length,
      total_chunks: result[:knowledge_chunks]&.count || 0,
      chunks_with_timestamp: chunks_with_ts.count,
      sample_chunks: result[:knowledge_chunks]&.first(3)&.map do |c|
        {
          type: c[:type],
          summary: c[:summary],
          timestamp_start: c[:timestamp_start],
          timestamp_end: c[:timestamp_end]
        }
      end
    }
  end

  # POST /admin/seed_exercises
  # Seed/update exercise data with form_tips
  def seed_exercises
    require_relative "../../db/seeds/exercises"

    before_count = Exercise.count
    seed_exercises_data

    render json: {
      success: true,
      message: "Exercises seeded",
      before_count: before_count,
      after_count: Exercise.count,
      with_form_tips: Exercise.where.not(form_tips: [nil, ""]).count
    }
  end

  # POST /admin/import_program_knowledge
  # Import workout programs from workout_programs.rb into RAG knowledge base
  def import_program_knowledge
    imported_count = 0

    # Create virtual YouTube channel/video for program knowledge
    channel = YoutubeChannel.find_or_create_by!(channel_id: "PROGRAM_KNOWLEDGE") do |c|
      c.name = "운동 프로그램 지식"
      c.handle = "@program_knowledge"
      c.url = "internal://program-knowledge"
      c.subscriber_count = 0
      c.video_count = 0
    end

    video = YoutubeVideo.find_or_create_by!(youtube_channel: channel, video_id: "PROGRAM_TEMPLATES") do |v|
      v.title = "운동 프로그램 템플릿"
      v.duration_seconds = 0
      v.analysis_status = "completed"
    end

    # Import programs
    errors = []
    [
      [AiTrainer::WorkoutPrograms::BEGINNER, "beginner"],
      [AiTrainer::WorkoutPrograms::INTERMEDIATE, "intermediate"],
      [AiTrainer::WorkoutPrograms::ADVANCED, "advanced"]
    ].each do |program, difficulty|
      begin
        imported_count += import_program(video, program, difficulty)
      rescue StandardError => e
        errors << "#{difficulty}: #{e.message}"
        Rails.logger.error("Import error for #{difficulty}: #{e.message}\n#{e.backtrace.first(5).join("\n")}")
      end
    end

    # Import special programs
    begin
      # SHIMHYUNDO has program structure like BEGINNER/INTERMEDIATE/ADVANCED
      if defined?(AiTrainer::WorkoutPrograms::SHIMHYUNDO)
        shimhyundo = AiTrainer::WorkoutPrograms::SHIMHYUNDO
        imported_count += import_shimhyundo_program(video, shimhyundo)
      end
    rescue StandardError => e
      errors << "SHIMHYUNDO: #{e.message}"
      Rails.logger.error("Import error for SHIMHYUNDO: #{e.message}\n#{e.backtrace.first(5).join("\n")}")
    end

    begin
      # KIMSUNGHWAN has phases structure
      if defined?(AiTrainer::WorkoutPrograms::KIMSUNGHWAN)
        kimsunghwan = AiTrainer::WorkoutPrograms::KIMSUNGHWAN
        imported_count += import_kimsunghwan_program(video, kimsunghwan)
      end
    rescue StandardError => e
      errors << "KIMSUNGHWAN: #{e.message}"
      Rails.logger.error("Import error for KIMSUNGHWAN: #{e.message}\n#{e.backtrace.first(5).join("\n")}")
    end

    render json: {
      success: errors.empty?,
      message: "Imported #{imported_count} program knowledge chunks",
      imported_count: imported_count,
      total_knowledge_chunks: FitnessKnowledgeChunk.count,
      routine_design_chunks: FitnessKnowledgeChunk.where(knowledge_type: "routine_design").count,
      errors: errors
    }
  end

  # POST /admin/import_knowledge_chunk
  # Import a single knowledge chunk from external source (Excel, etc.)
  def import_knowledge_chunk
    # Find or create the external knowledge video
    channel = YoutubeChannel.find_or_create_by!(channel_id: "EXTERNAL_KNOWLEDGE") do |c|
      c.name = "외부 지식 소스"
      c.handle = "@external_knowledge"
      c.url = "internal://external-knowledge"
      c.subscriber_count = 0
      c.video_count = 0
    end

    video = YoutubeVideo.find_or_create_by!(youtube_channel: channel, video_id: "EXTERNAL_DATA") do |v|
      v.title = "외부 데이터 소스"
      v.duration_seconds = 0
      v.analysis_status = "completed"
    end

    chunk = FitnessKnowledgeChunk.create!(
      youtube_video: video,
      knowledge_type: params[:knowledge_type] || "routine_design",
      content: params[:content],
      summary: params[:summary],
      exercise_name: params[:exercise_name],
      difficulty_level: params[:difficulty_level] || "all",
      timestamp_start: 0
    )

    render json: {
      success: true,
      chunk_id: chunk.id,
      message: "Knowledge chunk created"
    }
  rescue ActiveRecord::RecordInvalid => e
    render json: { success: false, error: e.message }, status: :unprocessable_entity
  end

  # GET /admin/check_pgvector
  # Check if pgvector is available and what extensions exist
  def check_pgvector
    available_extensions = ActiveRecord::Base.connection.execute(
      "SELECT name, default_version, installed_version FROM pg_available_extensions WHERE name LIKE '%vector%' OR name = 'vector'"
    ).to_a

    installed_extensions = ActiveRecord::Base.connection.execute(
      "SELECT extname, extversion FROM pg_extension"
    ).to_a

    # Try to enable vector extension
    enable_result = begin
      ActiveRecord::Base.connection.execute("CREATE EXTENSION IF NOT EXISTS vector")
      { success: true, message: "Extension enabled or already exists" }
    rescue StandardError => e
      { success: false, error: e.message }
    end

    # Check if embedding column exists
    columns = ActiveRecord::Base.connection.columns("fitness_knowledge_chunks").map(&:name)

    render json: {
      available_extensions: available_extensions,
      installed_extensions: installed_extensions,
      enable_vector_result: enable_result,
      embedding_column_exists: columns.include?("embedding"),
      all_columns: columns
    }
  end

  # GET /admin/embedding_status
  # Check embedding status and trigger embedding generation
  def embedding_status
    total = FitnessKnowledgeChunk.count
    embedding_column_exists = FitnessKnowledgeChunk.column_names.include?("embedding")

    with_embedding = embedding_column_exists ? FitnessKnowledgeChunk.where.not(embedding: nil).count : 0
    without_embedding = total - with_embedding

    render json: {
      total_chunks: total,
      with_embedding: with_embedding,
      without_embedding: without_embedding,
      coverage_percent: total > 0 ? (with_embedding.to_f / total * 100).round(1) : 0,
      embedding_column_exists: embedding_column_exists,
      pgvector_available: EmbeddingService.pgvector_available?,
      gemini_configured: EmbeddingService.configured?
    }
  end

  # POST /admin/generate_embeddings
  # Generate embeddings for chunks without them
  def generate_embeddings
    limit = [params[:limit]&.to_i || 100, 500].min

    unless FitnessKnowledgeChunk.column_names.include?("embedding")
      return render json: { success: false, error: "Embedding column does not exist. Run migrations first." }, status: :unprocessable_entity
    end

    unless EmbeddingService.configured?
      return render json: { success: false, error: "Gemini API not configured" }, status: :unprocessable_entity
    end

    unless EmbeddingService.pgvector_available?
      return render json: { success: false, error: "pgvector not available" }, status: :unprocessable_entity
    end

    # Run in background or synchronously based on limit
    if limit <= 50
      count = 0
      FitnessKnowledgeChunk.where(embedding: nil).limit(limit).find_each do |chunk|
        EmbeddingService.embed_knowledge_chunk(chunk)
        count += 1
      rescue StandardError => e
        Rails.logger.error("Failed to embed chunk #{chunk.id}: #{e.message}")
      end

      render json: {
        success: true,
        embedded_count: count,
        remaining: FitnessKnowledgeChunk.where(embedding: nil).count
      }
    else
      # Queue for background processing
      GenerateEmbeddingsJob.perform_async(limit) if defined?(GenerateEmbeddingsJob)

      render json: {
        success: true,
        message: "Embedding generation queued",
        limit: limit
      }
    end
  end

  # POST /admin/test_search
  # Test RAG search with a query - uses SAME logic as CreativeRoutineGenerator
  def test_search
    query = params[:query]
    return render json: { error: "query parameter required" }, status: :bad_request unless query.present?

    search_type = params[:search_type] || "semantic" # semantic, keyword
    knowledge_type = params[:knowledge_type] || "all"
    limit = [params[:limit]&.to_i || 10, 30].min
    user_level = params[:level]&.to_i || 3

    # Check if embedding column exists
    embedding_column_exists = FitnessKnowledgeChunk.column_names.include?("embedding")

    debug_info = {
      total_chunks: FitnessKnowledgeChunk.count,
      chunks_with_embedding: embedding_column_exists ? FitnessKnowledgeChunk.where.not(embedding: nil).count : 0,
      embedding_column_exists: embedding_column_exists,
      pgvector_available: EmbeddingService.pgvector_available?,
      gemini_configured: EmbeddingService.configured?,
      user_level: user_level,
      search_query_used: nil,
      actual_search_type: nil
    }

    # Use CreativeRoutineGenerator's search logic
    results, actual_type, search_query = search_like_routine_generator(
      query: query,
      search_type: search_type,
      knowledge_type: knowledge_type,
      limit: limit,
      user_level: user_level
    )

    debug_info[:actual_search_type] = actual_type
    debug_info[:search_query_used] = search_query

    render json: {
      success: true,
      query: query,
      search_type: actual_type,
      requested_search_type: search_type,
      knowledge_type: knowledge_type,
      result_count: results.size,
      results: results,
      debug: debug_info
    }
  rescue StandardError => e
    Rails.logger.error("Search test error: #{e.message}\n#{e.backtrace.first(5).join("\n")}")
    render json: { success: false, error: e.message, backtrace: e.backtrace.first(3) }, status: :internal_server_error
  end

  # POST /admin/extract_transcripts
  # Trigger transcript extraction for videos without transcripts
  # Use ?limit=100 (default)
  def extract_transcripts
    limit = [params[:limit]&.to_i || 100, 500].min
    language = params[:language] # "en", "ko", or nil for all

    scope = YoutubeVideo.where(transcript: [nil, ""])
                        .joins(:youtube_channel)
                        .where(youtube_channels: { active: true })
    scope = scope.where(youtube_channels: { language: language }) if language.present?
    without_transcript = scope.count

    if without_transcript == 0
      return render json: {
        success: true,
        message: "All videos already have transcripts",
        without_transcript: 0,
        language_filter: language
      }
    end

    ExtractTranscriptsJob.perform_async(limit, true, language)

    render json: {
      success: true,
      message: "Transcript extraction started",
      without_transcript: without_transcript,
      processing_limit: limit,
      estimated_minutes: (limit * 5.0 / 60).round(1)
    }
  end

  # GET /admin/transcript_status
  # Check transcript extraction progress
  def transcript_status
    total = YoutubeVideo.count
    with_transcript = YoutubeVideo.where.not(transcript: [nil, ""]).count
    without_transcript = total - with_transcript

    render json: {
      total: total,
      with_transcript: with_transcript,
      without_transcript: without_transcript,
      coverage_percent: (with_transcript.to_f / total * 100).round(1)
    }
  end

  # GET /admin/channel_status
  # Check videos per channel
  def channel_status
    channels = YoutubeChannel.all.map do |channel|
      videos = channel.youtube_videos
      with_transcript = videos.where.not(transcript: [nil, ""]).count
      {
        name: channel.name,
        handle: channel.handle,
        language: channel.language,
        total_videos: videos.count,
        with_transcript: with_transcript,
        active: channel.active
      }
    end

    render json: {
      channels: channels,
      total_channels: channels.count
    }
  end

  # GET /admin/reanalyze_status
  # Check reanalysis progress
  def reanalyze_status
    total = YoutubeVideo.count
    completed = YoutubeVideo.completed.count
    pending = YoutubeVideo.pending.count
    analyzing = YoutubeVideo.analyzing.count
    failed = YoutubeVideo.failed.count

    chunks_with_timestamp = FitnessKnowledgeChunk.where.not(timestamp_start: nil).count
    chunks_total = FitnessKnowledgeChunk.count

    render json: {
      videos: {
        total: total,
        completed: completed,
        pending: pending,
        analyzing: analyzing,
        failed: failed
      },
      chunks: {
        total: chunks_total,
        with_timestamp: chunks_with_timestamp,
        without_timestamp: chunks_total - chunks_with_timestamp
      }
    }
  end

  private

  def import_program(video, program, difficulty)
    count = 0
    program_name = program[:korean] || program[:level]
    program_data = program[:program]

    return 0 unless program_data.is_a?(Hash)

    program_data.each do |week_num, week_data|
      next unless week_data.is_a?(Hash)

      week_data.each do |day_num, day_data|
        next unless day_data.is_a?(Hash)

        training_type = day_data[:training_type]
        training_info = AiTrainer::WorkoutPrograms::TRAINING_TYPES[training_type] || {}

        content = build_day_content(program_name, week_num, day_num, day_data, training_info)
        exercises = day_data[:exercises] || []
        exercise_names = exercises.map { |ex| ex[:name] }.join(", ")

        FitnessKnowledgeChunk.find_or_create_by!(
          youtube_video: video,
          knowledge_type: "routine_design",
          summary: "#{program_name} #{week_num}주차 #{day_num}일: #{training_info[:korean] || training_type}"
        ) do |chunk|
          chunk.content = content
          chunk.exercise_name = exercise_names
          chunk.difficulty_level = difficulty
          chunk.timestamp_start = 0
        end
        count += 1
      end
    end
    count
  end

  def build_day_content(program_name, week_num, day_num, day_data, training_info)
    lines = []
    lines << "## #{program_name} - #{week_num}주차 #{day_num}일차"
    lines << ""
    lines << "### 훈련 유형: #{training_info[:korean] || day_data[:training_type]}"
    lines << training_info[:description] if training_info[:description]
    lines << ""
    lines << "### 운동 목록"

    exercises = day_data[:exercises] || []
    exercises.each_with_index do |ex, idx|
      exercise_line = "#{idx + 1}. #{ex[:name]}"
      exercise_line += " (#{ex[:target]})" if ex[:target]

      details = []
      details << "#{ex[:sets]}세트" if ex[:sets]
      details << "#{ex[:reps]}회" if ex[:reps]
      details << "BPM #{ex[:bpm]}" if ex[:bpm]
      details << "무게: #{ex[:weight]}" if ex[:weight]
      details << "ROM: #{ex[:rom]}" if ex[:rom]

      exercise_line += " - #{details.join(', ')}" if details.any?
      exercise_line += "\n   방법: #{ex[:how_to]}" if ex[:how_to]

      lines << exercise_line
    end

    if day_data[:purpose]
      lines << ""
      lines << "### 목적"
      lines << day_data[:purpose]
    end

    lines.join("\n")
  end

  def import_shimhyundo_program(video, program)
    count = 0
    program_name = program[:name] || "심현도 무분할"
    program_data = program[:program]

    return 0 unless program_data.is_a?(Hash)

    program_data.each do |level_num, level_data|
      next unless level_data.is_a?(Hash)

      level_data.each do |day_num, day_data|
        next unless day_data.is_a?(Hash)

        exercises = day_data[:exercises] || []
        exercise_names = exercises.map { |ex| ex[:name] }.join(", ")

        content = build_shimhyundo_content(program_name, level_num, day_num, exercises)

        FitnessKnowledgeChunk.find_or_create_by!(
          youtube_video: video,
          knowledge_type: "routine_design",
          summary: "#{program_name} 레벨#{level_num} #{day_num}일차"
        ) do |chunk|
          chunk.content = content
          chunk.exercise_name = exercise_names
          chunk.difficulty_level = level_num <= 3 ? "beginner" : (level_num <= 5 ? "intermediate" : "advanced")
          chunk.timestamp_start = 0
        end
        count += 1
      end
    end
    count
  end

  def build_shimhyundo_content(program_name, level_num, day_num, exercises)
    lines = []
    lines << "## #{program_name} - 레벨 #{level_num} #{day_num}일차"
    lines << ""
    lines << "### 운동 목록"

    exercises.each_with_index do |ex, idx|
      exercise_line = "#{idx + 1}. #{ex[:name]}"
      exercise_line += " (#{ex[:target]})" if ex[:target]

      details = []
      details << "#{ex[:sets]}세트" if ex[:sets]
      details << "#{ex[:reps]}회" if ex[:reps]
      details << "무게: #{ex[:weight]}" if ex[:weight]

      exercise_line += " - #{details.join(', ')}" if details.any?
      exercise_line += "\n   방법: #{ex[:how_to]}" if ex[:how_to]

      lines << exercise_line
    end

    lines.join("\n")
  end

  def import_kimsunghwan_program(video, program)
    count = 0
    program_name = program[:name] || "김성환 운동 루틴"
    phases = program[:phases]

    return 0 unless phases.is_a?(Hash)

    phases.each do |phase_key, phase_data|
      next unless phase_data.is_a?(Hash)

      phase_name = phase_data[:name] || phase_key.to_s
      exercises = phase_data[:exercises] || []
      exercise_names = exercises.map { |ex| ex[:name] }.join(", ")

      content = build_kimsunghwan_content(program_name, phase_name, phase_data, exercises)

      FitnessKnowledgeChunk.find_or_create_by!(
        youtube_video: video,
        knowledge_type: "routine_design",
        summary: "#{program_name} - #{phase_name}"
      ) do |chunk|
        chunk.content = content
        chunk.exercise_name = exercise_names
        chunk.difficulty_level = phase_key.to_s.include?("beginner") ? "beginner" : (phase_key.to_s.include?("intermediate") ? "intermediate" : "advanced")
        chunk.timestamp_start = 0
      end
      count += 1
    end
    count
  end

  def build_kimsunghwan_content(program_name, phase_name, phase_data, exercises)
    lines = []
    lines << "## #{program_name} - #{phase_name}"
    lines << ""
    lines << "- 기간: #{phase_data[:duration]}" if phase_data[:duration]
    lines << "- 빈도: #{phase_data[:frequency]}" if phase_data[:frequency]
    lines << "- 포커스: #{phase_data[:focus]}" if phase_data[:focus]
    lines << ""
    lines << "### 운동 목록"

    exercises.each_with_index do |ex, idx|
      exercise_line = "#{idx + 1}. #{ex[:name]}"
      exercise_line += " (#{ex[:target]})" if ex[:target]

      details = []
      details << "#{ex[:sets]}세트" if ex[:sets]
      details << "#{ex[:reps]}회" if ex[:reps]

      exercise_line += " - #{details.join(', ')}" if details.any?
      lines << exercise_line
    end

    lines.join("\n")
  end

  def import_special_program(video, program, name)
    content = build_special_program_content(program, name)

    FitnessKnowledgeChunk.find_or_create_by!(
      youtube_video: video,
      knowledge_type: "routine_design",
      summary: "#{name} 루틴 프로그램"
    ) do |chunk|
      chunk.content = content
      chunk.exercise_name = extract_all_exercises(program)
      chunk.difficulty_level = "all"
      chunk.timestamp_start = 0
    end
  end

  def build_special_program_content(program, name)
    lines = ["## #{name} 운동 프로그램", ""]

    if program[:description]
      lines << program[:description]
      lines << ""
    end

    if program[:levels]
      program[:levels].each do |level_num, level_data|
        lines << "### 레벨 #{level_num}"
        lines.concat(format_exercises(level_data[:exercises])) if level_data[:exercises]
        lines << ""
      end
    elsif program[:phases]
      program[:phases].each do |phase_name, phase_data|
        lines << "### #{phase_name} 페이즈"
        lines.concat(format_exercises(phase_data[:exercises])) if phase_data[:exercises]
        lines << ""
      end
    end

    lines.join("\n")
  end

  def format_exercises(exercises)
    return [] unless exercises

    exercises.map.with_index do |ex, idx|
      line = "#{idx + 1}. #{ex[:name]}"
      details = []
      details << "#{ex[:sets]}세트" if ex[:sets]
      details << "#{ex[:reps]}회" if ex[:reps]
      line += " - #{details.join(', ')}" if details.any?
      line
    end
  end

  def extract_all_exercises(program)
    exercises = []

    if program[:levels]
      program[:levels].each_value do |level_data|
        exercises.concat(level_data[:exercises]&.map { |ex| ex[:name] } || [])
      end
    elsif program[:phases]
      program[:phases].each_value do |phase_data|
        exercises.concat(phase_data[:exercises]&.map { |ex| ex[:name] } || [])
      end
    end

    exercises.uniq.join(", ")
  end

  # Search using the SAME logic as CreativeRoutineGenerator
  def search_like_routine_generator(query:, search_type:, knowledge_type:, limit:, user_level:)
    # Translate query to English for better embedding search
    english_query = translate_query_for_embedding(query)

    # Extract target muscles from query (same as CreativeRoutineGenerator)
    target_muscles = extract_target_muscles_from_query(query)

    # Build search query in English for embedding compatibility
    tier = AiTrainer::Constants.tier_for_level(user_level)
    search_query = "#{english_query} exercise workout fitness #{tier}"

    actual_type = search_type
    results = []

    # Determine which knowledge types to search
    types_to_search = if knowledge_type == "all"
                        %w[routine_design exercise_technique]
                      else
                        [knowledge_type]
                      end

    types_to_search.each do |ktype|
      chunks, used_type = search_chunks_like_generator(
        query: search_query,
        knowledge_type: ktype,
        limit: limit / types_to_search.size,
        user_level: user_level,
        target_muscles: target_muscles,
        force_keyword: search_type == "keyword"
      )
      actual_type = used_type
      results += chunks
    end

    formatted_results = results.map do |chunk|
      {
        id: chunk[:id],
        type: chunk[:knowledge_type],
        difficulty: chunk[:difficulty_level],
        exercise_name: chunk[:exercise_name],
        muscle_group: chunk[:muscle_group],
        summary: chunk[:summary],
        content: chunk[:content]&.truncate(500),
        has_embedding: chunk[:has_embedding],
        similarity_score: chunk[:similarity_score],
        source: {
          video_title: chunk[:video_title],
          channel: chunk[:channel_name]
        }
      }
    end

    [formatted_results, actual_type, search_query]
  end

  # Same logic as CreativeRoutineGenerator#search_with_embeddings
  def search_chunks_like_generator(query:, knowledge_type:, limit:, user_level:, target_muscles:, force_keyword: false)
    embedding_column_exists = FitnessKnowledgeChunk.column_names.include?("embedding")
    actual_type = "keyword"

    # Try semantic search first (if not forced keyword and embeddings available)
    if !force_keyword && embedding_column_exists && EmbeddingService.pgvector_available? && EmbeddingService.configured?
      begin
        query_embedding = EmbeddingService.generate_query_embedding(query)

        if query_embedding.present?
          # Hybrid search: semantic + muscle_group filter
          base_scope = FitnessKnowledgeChunk
            .where(knowledge_type: knowledge_type)
            .where.not(embedding: nil)
            .for_user_level(user_level)
            .includes(:youtube_video)

          # Apply muscle_group filter if target muscles specified
          if target_muscles.any?
            muscle_conditions = target_muscles.map { "muscle_group ILIKE ?" }
            muscle_values = target_muscles.map { |m| "%#{m}%" }
            base_scope = base_scope.where(muscle_conditions.join(" OR "), *muscle_values)
          end

          chunks = base_scope
            .nearest_neighbors(:embedding, query_embedding, distance: "cosine")
            .limit(limit)

          if chunks.any?
            actual_type = target_muscles.any? ? "semantic+muscle_filter" : "semantic"
            results = chunks.map do |c|
              {
                id: c.id,
                knowledge_type: c.knowledge_type,
                difficulty_level: c.difficulty_level,
                exercise_name: c.exercise_name,
                muscle_group: c.muscle_group,
                summary: c.summary,
                content: c.content,
                has_embedding: true,
                similarity_score: c.respond_to?(:neighbor_distance) ? (1 - c.neighbor_distance).round(4) : nil,
                video_title: c.youtube_video&.title,
                channel_name: c.youtube_video&.youtube_channel&.name
              }
            end
            return [results, actual_type]
          end
        end
      rescue StandardError => e
        Rails.logger.warn("Semantic search failed: #{e.message}")
      end
    end

    # Fallback to keyword search (same as CreativeRoutineGenerator#keyword_search)
    actual_type = force_keyword ? "keyword" : "keyword (fallback)"
    keywords = query.split(/\s+/).reject { |w| w.length < 2 }

    scope = FitnessKnowledgeChunk
      .where(knowledge_type: knowledge_type)
      .for_user_level(user_level)
      .includes(:youtube_video)

    # Filter by target muscles for exercise_technique (same as generator)
    if target_muscles.any? && knowledge_type == "exercise_technique"
      muscle_conditions = target_muscles.map { "muscle_group ILIKE ? OR exercise_name ILIKE ? OR content ILIKE ?" }
      muscle_values = target_muscles.flat_map { |m| ["%#{m}%", "%#{m}%", "%#{m}%"] }
      scope = scope.where(muscle_conditions.join(" OR "), *muscle_values)
    end

    # Search by keywords in content/summary
    if keywords.any?
      keyword_conditions = keywords.map { "content ILIKE ? OR summary ILIKE ?" }
      keyword_values = keywords.flat_map { |kw| ["%#{kw}%", "%#{kw}%"] }
      scope = scope.where(keyword_conditions.join(" OR "), *keyword_values)
    end

    chunks = scope.order(Arel.sql("RANDOM()")).limit(limit)

    results = chunks.map do |c|
      {
        id: c.id,
        knowledge_type: c.knowledge_type,
        difficulty_level: c.difficulty_level,
        exercise_name: c.exercise_name,
        muscle_group: c.muscle_group,
        summary: c.summary,
        content: c.content,
        has_embedding: embedding_column_exists && c.embedding.present?,
        similarity_score: nil,
        video_title: c.youtube_video&.title,
        channel_name: c.youtube_video&.youtube_channel&.name
      }
    end

    [results, actual_type]
  end

  # Translate Korean fitness query to English for better embedding search
  def translate_query_for_embedding(query)
    return query if query.match?(/\A[a-zA-Z0-9\s]+\z/) # Already English

    system_prompt = "You are a fitness query translator. Translate the Korean fitness query to English. Keep it concise and focused on fitness terms. Only output the English translation, nothing else."

    result = AiTrainer::LlmGateway.chat(
      prompt: query,
      task: :query_translation,
      system: system_prompt,
      cache_system: false
    )

    if result[:success] && result[:content].present?
      translated = result[:content].strip
      Rails.logger.info("[Search] Translated '#{query}' -> '#{translated}'")
      translated
    else
      Rails.logger.warn("[Search] Translation failed, using original query")
      query
    end
  rescue StandardError => e
    Rails.logger.error("[Search] Translation error: #{e.message}")
    query
  end

  # Same logic as CreativeRoutineGenerator#extract_target_muscles
  def extract_target_muscles_from_query(query)
    # Map Korean keywords to English muscle_group values (matching DB)
    muscle_keywords = {
      "back" => %w[등 back 광배 승모 lat],
      "chest" => %w[가슴 chest 흉근 대흉근 pec],
      "shoulders" => %w[어깨 shoulder 삼각근 deltoid],
      "arms" => %w[팔 arm 이두 삼두 bicep tricep],
      "legs" => %w[하체 leg 다리 허벅지 대퇴 quadricep hamstring],
      "core" => %w[코어 core 복근 abs 복부],
      "full_body" => %w[전신 full body 전체]
    }

    query_lower = query.downcase
    matched_muscles = []

    muscle_keywords.each do |muscle_en, keywords|
      matched_muscles << muscle_en if keywords.any? { |kw| query_lower.include?(kw) }
    end

    matched_muscles
  end

  # Legacy method - kept for compatibility
  def perform_search_with_type(query:, search_type:, knowledge_type:, limit:)
    scope = if knowledge_type == "all"
              FitnessKnowledgeChunk.all
            else
              FitnessKnowledgeChunk.where(knowledge_type: knowledge_type)
            end

    chunks, actual_type = case search_type
    when "semantic"
      [semantic_search(query, scope, limit), @actual_search_type || "semantic"]
    when "keyword"
      [keyword_search(query, scope, limit), "keyword"]
    when "hybrid"
      [hybrid_search(query, scope, limit), "hybrid"]
    else
      [semantic_search(query, scope, limit), @actual_search_type || "semantic"]
    end

    results = chunks.map do |chunk|
      {
        id: chunk.id,
        type: chunk.knowledge_type,
        difficulty: chunk.difficulty_level,
        exercise_name: chunk.exercise_name,
        muscle_group: chunk.muscle_group,
        summary: chunk.summary,
        content: chunk.content&.truncate(500),
        has_embedding: chunk.embedding.present?,
        similarity_score: chunk.respond_to?(:neighbor_distance) ? (1 - chunk.neighbor_distance).round(4) : nil,
        source: {
          video_title: chunk.youtube_video&.title,
          channel: chunk.youtube_video&.youtube_channel&.name
        }
      }
    end

    [results, actual_type]
  end

  def semantic_search(query, scope, limit)
    # Check if embedding column exists
    unless FitnessKnowledgeChunk.column_names.include?("embedding")
      Rails.logger.warn("Embedding column does not exist, falling back to keyword")
      @actual_search_type = "keyword (no embedding column)"
      return keyword_search(query, scope, limit)
    end

    unless EmbeddingService.pgvector_available? && EmbeddingService.configured?
      Rails.logger.warn("Semantic search unavailable, falling back to keyword")
      @actual_search_type = "keyword (pgvector/gemini unavailable)"
      return keyword_search(query, scope, limit)
    end

    # Check if there are any chunks with embeddings
    chunks_with_embeddings = scope.where.not(embedding: nil).count
    if chunks_with_embeddings == 0
      Rails.logger.warn("No chunks with embeddings found, falling back to keyword")
      @actual_search_type = "keyword (no embeddings)"
      return keyword_search(query, scope, limit)
    end

    query_embedding = EmbeddingService.generate_query_embedding(query)
    unless query_embedding.present?
      Rails.logger.warn("Failed to generate query embedding, falling back to keyword")
      @actual_search_type = "keyword (embedding failed)"
      return keyword_search(query, scope, limit)
    end

    @actual_search_type = "semantic"
    results = scope.where.not(embedding: nil)
                   .nearest_neighbors(:embedding, query_embedding, distance: "cosine")
                   .limit(limit)

    # If semantic search returns no results, try keyword fallback
    if results.empty?
      Rails.logger.warn("Semantic search returned no results, falling back to keyword")
      @actual_search_type = "keyword (no semantic matches)"
      return keyword_search(query, scope, limit)
    end

    results
  end

  def keyword_search(query, scope, limit)
    # Extract keywords from query
    keywords = query.downcase.split(/[\s,]+/).reject { |w| w.length < 2 }

    return scope.limit(limit) if keywords.empty?

    # Build search conditions
    conditions = keywords.map do |keyword|
      sanitized = ActiveRecord::Base.sanitize_sql_like(keyword)
      "(LOWER(content) LIKE '%#{sanitized}%' OR LOWER(summary) LIKE '%#{sanitized}%' OR LOWER(exercise_name) LIKE '%#{sanitized}%')"
    end

    scope.where(conditions.join(" OR "))
         .order(Arel.sql("CASE WHEN LOWER(summary) LIKE '%#{ActiveRecord::Base.sanitize_sql_like(keywords.first)}%' THEN 0 ELSE 1 END"))
         .limit(limit)
  end

  def hybrid_search(query, scope, limit)
    # Combine semantic and keyword results
    semantic_results = semantic_search(query, scope, limit / 2)
    keyword_results = keyword_search(query, scope, limit / 2)

    # Merge and dedupe, prioritizing semantic results
    seen_ids = Set.new
    combined = []

    semantic_results.each do |chunk|
      next if seen_ids.include?(chunk.id)
      seen_ids.add(chunk.id)
      combined << chunk
    end

    keyword_results.each do |chunk|
      next if seen_ids.include?(chunk.id)
      seen_ids.add(chunk.id)
      combined << chunk
      break if combined.size >= limit
    end

    combined.first(limit)
  end

  def verify_admin_token
    token = request.headers["X-Admin-Token"] || params[:admin_token]
    expected = ENV["ADMIN_SECRET_TOKEN"]

    unless expected.present? && ActiveSupport::SecurityUtils.secure_compare(token.to_s, expected)
      render json: { error: "Unauthorized" }, status: :unauthorized
    end
  end

  def get_or_create_test_user(level = 5, user_type: "existing_with_data")
    if user_type == "new"
      # 신규 유저: 레벨 1, form_onboarding 완료 but AI onboarding 미완료
      email = "test_new@repstack.io"
      name = "신규 테스트 유저"
      target_level = 1
      onboarding_complete = false
    else
      # 기존 유저: 선택한 레벨, 온보딩 완료 상태
      email = "test@repstack.io"
      name = "기존 테스트 유저"
      target_level = level
      onboarding_complete = true
    end

    user = User.find_or_create_by!(email: email) do |u|
      u.password = SecureRandom.hex(16)
      u.name = name
    end

    user.user_profile ||= user.create_user_profile!
    
    # Update profile
    profile_updates = { numeric_level: target_level }
    
    if onboarding_complete
      # 기존 유저: 온보딩 완료 상태로 설정
      profile_updates[:onboarding_completed_at] = Time.current unless user.user_profile.onboarding_completed_at
      profile_updates[:form_onboarding_completed_at] = Time.current unless user.user_profile.form_onboarding_completed_at
    else
      # 신규 유저: form_onboarding만 완료, AI onboarding 미완료
      # 단, 이미 상담 완료된 경우 리셋하지 않음
      profile_updates[:form_onboarding_completed_at] = Time.current unless user.user_profile.form_onboarding_completed_at
      # onboarding_completed_at은 이미 완료된 경우 유지
    end
    
    user.user_profile.update!(profile_updates)

    token = JsonWebToken.encode(user_id: user.id)
    [user, token]
  end

  def chat_html
    <<~HTML
      <!DOCTYPE html>
      <html lang="ko">
      <head>
        <meta charset="UTF-8">
        <meta name="viewport" content="width=device-width, initial-scale=1.0">
        <title>AI Trainer API Test</title>
        <style>
          * { box-sizing: border-box; margin: 0; padding: 0; }
          body {
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
            background: #0f0f1a;
            color: #eee;
            height: 100vh;
            display: flex;
          }
          .left-panel {
            width: 320px;
            background: #16213e;
            border-right: 1px solid #0f3460;
            display: flex;
            flex-direction: column;
            overflow-y: auto;
          }
          .panel-section {
            padding: 16px;
            border-bottom: 1px solid #0f3460;
          }
          .panel-section h3 {
            font-size: 13px;
            color: #e94560;
            margin-bottom: 12px;
            text-transform: uppercase;
            letter-spacing: 1px;
          }
          .btn-grid {
            display: grid;
            grid-template-columns: 1fr 1fr;
            gap: 8px;
          }
          .test-btn {
            background: #0f3460;
            border: 1px solid #1a4a7a;
            color: #fff;
            padding: 10px 8px;
            border-radius: 8px;
            font-size: 12px;
            cursor: pointer;
            transition: all 0.2s;
            text-align: center;
          }
          .test-btn:hover { background: #1a4a7a; border-color: #e94560; }
          .test-btn.full { grid-column: span 2; }
          .test-btn.danger { border-color: #ff4444; color: #ff6b6b; }
          .test-btn.danger:hover { background: #4a1a1a; }
          .form-group { margin-bottom: 12px; }
          .form-group label { display: block; font-size: 11px; color: #888; margin-bottom: 4px; }
          .form-group select, .form-group input {
            width: 100%;
            background: #0f3460;
            border: 1px solid #1a4a7a;
            color: #fff;
            padding: 8px 12px;
            border-radius: 6px;
            font-size: 13px;
          }
          .user-info { background: #0f3460; padding: 12px; border-radius: 8px; font-size: 12px; }
          .user-info div { margin-bottom: 4px; }
          .user-info span { color: #e94560; }
          .right-panel { flex: 1; display: flex; flex-direction: column; }
          .header {
            background: #16213e;
            padding: 12px 20px;
            border-bottom: 1px solid #0f3460;
            display: flex;
            justify-content: space-between;
            align-items: center;
          }
          .header h1 { font-size: 18px; color: #e94560; }
          .header-actions { display: flex; gap: 8px; }
          .header-btn {
            background: #0f3460;
            border: 1px solid #1a4a7a;
            color: #fff;
            padding: 6px 12px;
            border-radius: 6px;
            font-size: 12px;
            cursor: pointer;
          }
          .header-btn:hover { border-color: #e94560; }
          .header-btn.active { background: #e94560; border-color: #e94560; }
          .main-content { flex: 1; display: flex; overflow: hidden; }
          .chat-area { flex: 1; display: flex; flex-direction: column; }
          .chat-container {
            flex: 1;
            overflow-y: auto;
            padding: 16px;
            display: flex;
            flex-direction: column;
            gap: 12px;
          }
          .message {
            max-width: 85%;
            padding: 12px 16px;
            border-radius: 12px;
            line-height: 1.5;
            font-size: 14px;
          }
          .message.user { background: #e94560; align-self: flex-end; border-bottom-right-radius: 4px; }
          .message.bot { background: #1a2744; align-self: flex-start; border-bottom-left-radius: 4px; border: 1px solid #0f3460; }
          .message.system { background: #2a2a4a; align-self: center; font-size: 12px; color: #888; }
          .loading-indicator {
            color: #aaa;
            font-style: italic;
            display: flex;
            align-items: center;
            gap: 10px;
          }
          .loading-indicator .spinner {
            width: 16px;
            height: 16px;
            border: 2px solid #444;
            border-top: 2px solid #e94560;
            border-radius: 50%;
            animation: spin 1s linear infinite;
          }
          .loading-indicator .dots::after { content: ''; animation: dots 1.5s infinite; }
          @keyframes dots { 0% { content: ''; } 25% { content: '.'; } 50% { content: '..'; } 75% { content: '...'; } }
          @keyframes spin { 0% { transform: rotate(0deg); } 100% { transform: rotate(360deg); } }
          .loading-indicator.generating { color: #e94560; font-weight: 500; }
          .message.error { background: #4a1a1a; border: 1px solid #ff4444; align-self: center; }
          .message .intent-badge { display: inline-block; background: #e94560; color: #fff; padding: 2px 8px; border-radius: 4px; font-size: 10px; margin-bottom: 8px; }
          .message .routine-card { margin-top: 12px; padding: 12px; background: #0f3460; border-radius: 8px; font-size: 13px; }
          .message .routine-card h4 { color: #e94560; margin-bottom: 8px; }
          .message .exercise-item { padding: 6px 0; border-bottom: 1px solid #1a4a7a; }
          .message .exercise-item:last-child { border-bottom: none; }
          .input-area { background: #16213e; padding: 12px 16px; border-top: 1px solid #0f3460; display: flex; gap: 8px; }
          .input-area input { flex: 1; background: #0f3460; border: 1px solid #1a4a7a; color: #fff; padding: 12px 16px; border-radius: 20px; font-size: 14px; outline: none; }
          .input-area input:focus { border-color: #e94560; }
          .input-area button { background: #e94560; color: #fff; border: none; padding: 12px 24px; border-radius: 20px; font-size: 14px; font-weight: 600; cursor: pointer; }
          .input-area button:hover { background: #ff6b6b; }
          .input-area button:disabled { background: #666; }
          .raw-panel { width: 400px; background: #0a0a15; border-left: 1px solid #0f3460; display: none; flex-direction: column; }
          .raw-panel.visible { display: flex; }
          .raw-panel h3 { padding: 12px 16px; background: #16213e; font-size: 13px; color: #e94560; border-bottom: 1px solid #0f3460; }
          .raw-content { flex: 1; overflow-y: auto; padding: 12px; }
          .raw-block { margin-bottom: 16px; }
          .raw-block h4 { font-size: 11px; color: #888; margin-bottom: 6px; text-transform: uppercase; }
          .raw-block pre { background: #16213e; padding: 12px; border-radius: 6px; font-size: 11px; overflow-x: auto; white-space: pre-wrap; color: #8f8; }
          .raw-block pre.error { color: #f88; }
        </style>
      </head>
      <body>
        <div class="left-panel">
          <div class="panel-section">
            <h3>⚙️ 설정</h3>
            <div class="form-group">
              <label>Admin Token</label>
              <input type="password" id="token" placeholder="Admin Token">
            </div>
            <div class="form-group">
              <label>User Type</label>
              <select id="userType">
                <option value="new">🆕 신규 유저 (Lv.1, 기록없음)</option>
                <option value="existing_with_data" selected>👤 기존 유저 (운동 데이터 O)</option>
                <option value="existing_without_data">👤 기존 유저 (운동 데이터 X)</option>
              </select>
            </div>
            <div class="form-group" id="levelGroup">
              <label>User Level (1-8)</label>
              <select id="level">
                <option value="1">1 - 입문</option>
                <option value="2">2 - 초급</option>
                <option value="3">3 - 초급+</option>
                <option value="4">4 - 중급</option>
                <option value="5" selected>5 - 중급+</option>
                <option value="6">6 - 중상급</option>
                <option value="7">7 - 고급</option>
                <option value="8">8 - 최고급</option>
              </select>
            </div>
          </div>
          <div class="panel-section">
            <h3>👤 테스트 유저</h3>
            <div class="user-info" id="userInfo">
              <div>ID: <span id="userId">-</span></div>
              <div>Level: <span id="userLevel">-</span></div>
              <div>Routines: <span id="userRoutines">-</span></div>
            </div>
            <div style="margin-top: 12px;">
              <button class="test-btn full" onclick="resetUser()">🔄 유저 리셋</button>
              <button class="test-btn full" style="margin-top: 8px; background:#2a6a4a; border-color:#3a8a5a;" onclick="setRandomFormComplete()">🎲 랜덤 폼 완료 상태</button>
            </div>
          </div>
          <div class="panel-section">
            <h3>💬 채팅 시작</h3>
            <div class="btn-grid">
              <button class="test-btn full" onclick="startChat()" style="background:#e94560;border-color:#e94560;">🚀 AI가 먼저 인사하기</button>
            </div>
          </div>
          <div class="panel-section">
            <h3>🚀 빠른 테스트</h3>
            <div class="btn-grid">
              <button class="test-btn" onclick="quickTest('등 운동 루틴 만들어줘')">등 루틴</button>
              <button class="test-btn" onclick="quickTest('가슴 운동 추천해줘')">가슴 루틴</button>
              <button class="test-btn" onclick="quickTest('하체 운동 루틴')">하체 루틴</button>
              <button class="test-btn" onclick="quickTest('전신 운동')">전신 루틴</button>
              <button class="test-btn" onclick="quickTest('오늘 피곤한데 운동 뭐해')">컨디션 반영</button>
              <button class="test-btn" onclick="quickTest('30분만 운동하고 싶어')">시간 제한</button>
            </div>
          </div>
          <div class="panel-section">
            <h3>💬 일반 질문 (RAG)</h3>
            <div class="btn-grid">
              <button class="test-btn" onclick="quickTest('스쿼트 자세 알려줘')">스쿼트 자세</button>
              <button class="test-btn" onclick="quickTest('벤치프레스 팁')">벤치 팁</button>
              <button class="test-btn" onclick="quickTest('데드리프트 허리 아파')">데드 허리</button>
              <button class="test-btn" onclick="quickTest('3분할 추천해줘')">3분할 추천</button>
            </div>
          </div>
          <div class="panel-section">
            <h3>🔄 루틴 수정</h3>
            <div class="btn-grid">
              <button class="test-btn" onclick="quickTest('이거 말고 다른 운동')">운동 교체</button>
              <button class="test-btn" onclick="quickTest('운동 하나 더 추가해줘')">운동 추가</button>
              <button class="test-btn full" onclick="quickTest('루틴 다시 만들어줘')">루틴 재생성</button>
            </div>
          </div>
          <div class="panel-section">
            <h3>✅ 운동 완료 & 피드백</h3>
            <div class="btn-grid">
              <button class="test-btn full" onclick="quickTest('운동 끝났어')" style="background:#28a745;border-color:#28a745;">💪 운동 완료!</button>
              <button class="test-btn" onclick="quickTest('오늘 운동 좋았어, 적당했어')">😊 좋았어</button>
              <button class="test-btn" onclick="quickTest('오늘 운동 힘들었어, 너무 빡셌어')">😓 힘들었어</button>
              <button class="test-btn" onclick="quickTest('오늘 운동 쉬웠어, 좀 더 할 수 있었어')">😎 쉬웠어</button>
              <button class="test-btn" onclick="quickTest('어깨가 좀 아팠어')">🤕 통증 있었어</button>
            </div>
          </div>
          <div class="panel-section">
            <h3>🗑️ 관리</h3>
            <div class="btn-grid">
              <button class="test-btn danger" onclick="clearChat()">채팅 클리어</button>
              <button class="test-btn danger" onclick="deleteRoutines()">루틴 삭제</button>
            </div>
          </div>
        </div>
        <div class="right-panel">
          <div class="header">
            <h1>🏋️ AI Trainer API Test</h1>
            <div class="header-actions">
              <button class="header-btn" id="toggleRaw" onclick="toggleRawPanel()">Raw 보기</button>
              <button class="header-btn" onclick="refreshUserInfo()">새로고침</button>
            </div>
          </div>
          <div class="main-content">
            <div class="chat-area">
              <div class="chat-container" id="chat"></div>
              <div class="input-area">
                <input type="text" id="message" placeholder="메시지 입력..." autofocus>
                <button id="send" onclick="sendMessage()">전송</button>
              </div>
            </div>
            <div class="raw-panel" id="rawPanel">
              <h3>📋 Raw API Response</h3>
              <div class="raw-content">
                <div class="raw-block"><h4>Request</h4><pre id="rawRequest">-</pre></div>
                <div class="raw-block"><h4>Response</h4><pre id="rawResponse">-</pre></div>
              </div>
            </div>
          </div>
        </div>
        <script>
          const chat = document.getElementById('chat');
          const input = document.getElementById('message');
          const sendBtn = document.getElementById('send');
          const levelSelect = document.getElementById('level');
          const userTypeSelect = document.getElementById('userType');
          const levelGroup = document.getElementById('levelGroup');
          const tokenInput = document.getElementById('token');
          let sessionId = 'admin_' + Date.now();
          let currentRoutineId = null;
          let testUserId = null;  // Will be set from test_user_info response

          tokenInput.value = localStorage.getItem('admin_token') || new URLSearchParams(window.location.search).get('admin_token') || '';
          tokenInput.addEventListener('change', () => localStorage.setItem('admin_token', tokenInput.value));
          levelSelect.addEventListener('change', () => refreshUserInfo());
          userTypeSelect.addEventListener('change', () => {
            levelGroup.style.display = userTypeSelect.value === 'new' ? 'none' : 'block';
            sessionId = 'admin_' + Date.now();
            currentRoutineId = null;
            refreshUserInfo();
          });

          document.addEventListener('DOMContentLoaded', () => {
            addSystemMessage('API 테스트 준비 완료. 좌측 버튼으로 빠른 테스트 가능!');
            refreshUserInfo();
          });

          function getToken() {
            const token = tokenInput.value;
            if (!token) { alert('Admin Token을 입력하세요'); return null; }
            return token;
          }

          function addMessage(text, type, extra = {}) {
            const div = document.createElement('div');
            div.className = 'message ' + type;
            let html = '';
            if (extra.intent) html += '<span class="intent-badge">' + extra.intent + '</span><br>';
            html += text.replace(/\\n/g, '<br>');
            if (extra.routine) html += formatRoutineCard(extra.routine);
            div.innerHTML = html;
            chat.appendChild(div);
            chat.scrollTop = chat.scrollHeight;
          }

          function addSystemMessage(text) {
            const div = document.createElement('div');
            div.className = 'message system';
            div.textContent = text;
            chat.appendChild(div);
            chat.scrollTop = chat.scrollHeight;
          }

          function formatRoutineCard(routine) {
            if (!routine) return '';
            let html = '<div class="routine-card">';
            html += '<h4>📋 ' + (routine.day_korean || routine.dayKorean || '루틴') + '</h4>';
            const duration = routine.estimated_duration_minutes || routine.estimatedDurationMinutes;
            if (duration) html += '<div>⏱️ ' + duration + '분</div>';
            if (routine.exercises && routine.exercises.length > 0) {
              routine.exercises.forEach((ex, i) => {
                const name = ex.exercise_name || ex.exerciseName || '운동';
                const sets = ex.sets || '?';
                const reps = ex.reps || '?';
                html += '<div class="exercise-item">';
                html += '<strong>' + (i+1) + '. ' + name + '</strong>';
                html += ' - ' + sets + '세트 x ' + reps + '회';
                html += '</div>';
              });
            }
            const routineId = routine.routine_id || routine.routineId;
            if (routineId) {
              html += '<div style="margin-top:8px;font-size:11px;color:#888;">ID: ' + routineId + '</div>';
              currentRoutineId = routineId;
            }
            html += '</div>';
            return html;
          }

          async function sendMessage(customMessage = null, allowEmpty = false) {
            const message = customMessage !== null ? customMessage : input.value.trim();
            if (!message && !allowEmpty) return;
            const token = getToken();
            if (!token) return;
            if (!customMessage) { addMessage(message, 'user'); input.value = ''; }
            sendBtn.disabled = true;

            // Show loading indicator
            const loadingId = 'loading-' + Date.now();
            const loadingDiv = document.createElement('div');
            loadingDiv.id = loadingId;
            loadingDiv.className = 'message bot';
            loadingDiv.innerHTML = '<div class="loading-indicator generating"><span class="spinner"></span>AI가 응답을 생성하고 있어요<span class="dots"></span></div>';
            chat.appendChild(loadingDiv);
            chat.scrollTop = chat.scrollHeight;

            const reqBody = { message, level: levelSelect.value, user_type: userTypeSelect.value, session_id: sessionId, routine_id: currentRoutineId, test_user_id: testUserId };
            document.getElementById('rawRequest').textContent = JSON.stringify(reqBody, null, 2);
            try {
              const res = await fetch('/admin/chat?admin_token=' + encodeURIComponent(token), {
                method: 'POST',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify(reqBody)
              });
              const data = await res.json();

              // Remove loading indicator
              document.getElementById(loadingId)?.remove();

              document.getElementById('rawResponse').textContent = JSON.stringify(data, null, 2);
              document.getElementById('rawResponse').className = data.success ? '' : 'error';
              if (data.success) {
                addMessage(data.message || '(응답 없음)', 'bot', { intent: data.intent, routine: data.data?.routine });
                if (data.data?.routine?.routineId) currentRoutineId = data.data.routine.routineId;
              } else {
                addMessage('Error: ' + (data.error || 'Unknown'), 'error');
              }
              refreshUserInfo();
            } catch (e) {
              // Remove loading indicator on error
              document.getElementById(loadingId)?.remove();
              addMessage('Network Error: ' + e.message, 'error');
              document.getElementById('rawResponse').textContent = e.message;
              document.getElementById('rawResponse').className = 'error';
            }
            sendBtn.disabled = false;
            input.focus();
          }

          function quickTest(message) { addMessage(message, 'user'); sendMessage(message); }

          // AI가 먼저 인사하도록 빈 메시지 전송
          // - 신규 유저: AI 상담 시작 (폼 정보 기반 인사)
          // - 기존 유저: Daily greeting (어제 운동 요약 + 컨디션 질문)
          async function startChat() {
            const token = getToken();
            if (!token) return;
            const userType = userTypeSelect.value;
            const label = userType === 'new' ? 'AI 상담' : 'Daily Greeting';
            sendBtn.disabled = true;

            // Show loading indicator
            const loadingId = 'loading-start-' + Date.now();
            const loadingDiv = document.createElement('div');
            loadingDiv.id = loadingId;
            loadingDiv.className = 'message bot';
            loadingDiv.innerHTML = '<div class="loading-indicator generating"><span class="spinner"></span>' + label + ' 준비 중<span class="dots"></span></div>';
            chat.appendChild(loadingDiv);
            chat.scrollTop = chat.scrollHeight;

            const reqBody = { message: '', level: levelSelect.value, user_type: userType, session_id: sessionId, routine_id: null };
            document.getElementById('rawRequest').textContent = JSON.stringify(reqBody, null, 2);
            try {
              const res = await fetch('/admin/chat?admin_token=' + encodeURIComponent(token), {
                method: 'POST',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify(reqBody)
              });
              const data = await res.json();

              // Remove loading indicator
              document.getElementById(loadingId)?.remove();

              document.getElementById('rawResponse').textContent = JSON.stringify(data, null, 2);
              document.getElementById('rawResponse').className = data.success ? '' : 'error';
              if (data.success) {
                addMessage(data.message || '(응답 없음)', 'bot', { intent: data.intent });
              } else {
                addMessage('Error: ' + (data.error || 'Unknown'), 'error');
              }
              refreshUserInfo();
            } catch (e) {
              document.getElementById(loadingId)?.remove();
              addMessage('Network Error: ' + e.message, 'error');
            }
            sendBtn.disabled = false;
          }

          async function refreshUserInfo() {
            const token = getToken();
            if (!token) return;
            try {
              const res = await fetch('/admin/test_user_info?admin_token=' + encodeURIComponent(token) + '&level=' + levelSelect.value + '&user_type=' + userTypeSelect.value);
              const data = await res.json();
              const userTypeLabel = userTypeSelect.value === 'new' ? '🆕' : '👤';
              document.getElementById('userId').textContent = userTypeLabel + ' ' + (data.id || '-');
              document.getElementById('userLevel').textContent = data.level || '-';
              document.getElementById('userRoutines').textContent = data.recent_routines?.length || '0';
            } catch (e) { console.error('Failed to fetch user info:', e); }
          }

          async function resetUser() {
            const token = getToken();
            if (!token) return;
            const userType = userTypeSelect.value;
            const level = levelSelect.value;
            const labels = {
              'new': '신규',
              'existing_with_data': '기존(데이터O)',
              'existing_without_data': '기존(데이터X)'
            };
            const label = labels[userType] || '기존';
            if (!confirm(label + ' 테스트 유저를 리셋하시겠습니까?')) return;
            try {
              const res = await fetch('/admin/reset_test_user?admin_token=' + encodeURIComponent(token) + '&user_type=' + userType + '&level=' + level, { method: 'POST' });
              const data = await res.json();
              addSystemMessage('✅ ' + label + ' 유저 리셋 완료 (프로그램: ' + (data.has_program ? 'O' : 'X') + ', 운동기록: ' + (data.has_workout_data ? 'O' : 'X') + ')');
              currentRoutineId = null;
              sessionId = 'admin_' + Date.now();
              refreshUserInfo();
            } catch (e) { addMessage('Reset Error: ' + e.message, 'error'); }
          }

          async function setRandomFormComplete() {
            const token = getToken();
            if (!token) return;
            const userType = userTypeSelect.value;

            // Show loading indicator
            const loadingId = 'loading-form-' + Date.now();
            const loadingDiv = document.createElement('div');
            loadingDiv.id = loadingId;
            loadingDiv.className = 'message bot';
            loadingDiv.innerHTML = '<div class="loading-indicator generating"><span class="spinner"></span>랜덤 프로필 생성 중<span class="dots"></span></div>';
            chat.appendChild(loadingDiv);
            chat.scrollTop = chat.scrollHeight;

            try {
              const res = await fetch('/admin/random_form_complete?admin_token=' + encodeURIComponent(token) + '&user_type=' + userType, { method: 'POST' });
              const data = await res.json();

              // Remove loading indicator
              document.getElementById(loadingId)?.remove();

              if (data.success) {
                addSystemMessage('🎲 랜덤 폼 완료 상태 설정!');
                addSystemMessage('  - 경험: ' + data.profile.experience_level);
                addSystemMessage('  - 목표: ' + data.profile.fitness_goal);
                addSystemMessage('  - 키/체중: ' + data.profile.height + 'cm / ' + data.profile.weight + 'kg');
                sessionId = 'admin_' + Date.now();
                currentRoutineId = null;
                refreshUserInfo();
                // Display AI greeting (AI starts the conversation)
                if (data.ai_greeting) {
                  addMessage(data.ai_greeting, 'assistant');
                }
              } else {
                addMessage('Error: ' + (data.error || 'Unknown'), 'error');
              }
            } catch (e) {
              document.getElementById(loadingId)?.remove();
              addMessage('Error: ' + e.message, 'error');
            }
          }

          async function deleteRoutines() {
            const token = getToken();
            if (!token) return;
            const userType = userTypeSelect.value;
            if (!confirm('선택된 유저의 모든 루틴을 삭제하시겠습니까?')) return;
            try {
              const res = await fetch('/admin/delete_test_routines?admin_token=' + encodeURIComponent(token) + '&user_type=' + userType, { method: 'POST' });
              const data = await res.json();
              addSystemMessage('✅ 루틴 ' + (data.deleted || 0) + '개 삭제됨');
              currentRoutineId = null;
              refreshUserInfo();
            } catch (e) { addMessage('Delete Error: ' + e.message, 'error'); }
          }

          function clearChat() { chat.innerHTML = ''; addSystemMessage('채팅 클리어됨'); }
          function toggleRawPanel() { document.getElementById('rawPanel').classList.toggle('visible'); document.getElementById('toggleRaw').classList.toggle('active'); }
          input.addEventListener('keypress', (e) => { if (e.key === 'Enter') sendMessage(); });
        </script>
      </body>
      </html>
    HTML
  end
end
