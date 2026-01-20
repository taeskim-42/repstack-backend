#!/usr/bin/env ruby
# frozen_string_literal: true

# User Simulation Script
# Simulates a user's 12-week fitness journey with random conditions and feedback

require "net/http"
require "json"
require "uri"

API_URL = "https://repstack-backend-production.up.railway.app/graphql"

class UserSimulator
  attr_reader :token, :user_id, :week, :day, :total_workouts, :current_level, :history

  def initialize
    @history = []
    @total_workouts = 0
    @current_level = 1
    @week = 0
    @day = 0
  end

  def run(weeks: 12)
    puts "=" * 60
    puts "🏋️ AI Trainer 12주 시뮬레이션 시작"
    puts "=" * 60
    puts

    # Sign up
    sign_up
    return unless @token

    puts "✅ 회원가입 완료 (User ID: #{@user_id})"
    puts

    # Initial level test
    initial_level_test
    puts

    # Simulate weeks
    weeks.times do |week_num|
      @week = week_num + 1
      simulate_week

      # Check level test eligibility every 2 weeks
      if @week % 2 == 0
        check_and_do_level_test
      end

      puts
    end

    # Print summary
    print_summary
  end

  private

  def graphql_request(query, auth: true, **variables)
    uri = URI(API_URL)
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true
    http.read_timeout = 120

    request = Net::HTTP::Post.new(uri.path)
    request["Content-Type"] = "application/json"
    request["Authorization"] = "Bearer #{@token}" if auth && @token

    request.body = { query: query, variables: variables }.to_json

    response = http.request(request)
    JSON.parse(response.body)
  rescue => e
    puts "❌ API Error: #{e.message}"
    nil
  end

  def sign_up
    timestamp = Time.now.to_i
    email = "sim_user_#{timestamp}@test.com"

    query = <<~GQL
      mutation SignUp($input: SignUpInput!) {
        signUp(input: $input) {
          authPayload { token user { id email } }
          errors
        }
      }
    GQL

    result = graphql_request(query, auth: false,
      input: { name: "Simulation User", email: email, password: "password123" }
    )

    if result&.dig("data", "signUp", "authPayload", "token")
      @token = result["data"]["signUp"]["authPayload"]["token"]
      @user_id = result["data"]["signUp"]["authPayload"]["user"]["id"]
    else
      puts "❌ 회원가입 실패: #{result&.dig("data", "signUp", "errors")}"
    end
  end

  def initial_level_test
    puts "📝 초기 레벨 테스트 진행 중..."

    query = <<~GQL
      mutation LevelTest($input: LevelAssessmentInput!) {
        levelTest(input: $input) {
          success
          level
          recommendations
        }
      }
    GQL

    result = graphql_request(query,
      input: {
        experienceLevel: "BEGINNER",
        workoutFrequency: 3,
        strengthLevel: "BEGINNER",
        enduranceLevel: "BEGINNER",
        fitnessGoals: ["MUSCLE_GAIN", "STRENGTH"]
      }
    )

    if result&.dig("data", "levelTest", "success")
      level = result["data"]["levelTest"]["level"]
      puts "✅ 초기 레벨: #{level}"
    end
  end

  def simulate_week
    puts "-" * 60
    puts "📅 Week #{@week}"
    puts "-" * 60

    # Workout 5 days (Mon-Fri)
    (1..5).each do |day_of_week|
      @day = day_of_week
      simulate_day(day_of_week)
      sleep(1) # Rate limiting
    end

    puts "   📊 Week #{@week} 완료: 총 #{@total_workouts}회 운동, 현재 레벨 #{@current_level}"
  end

  def simulate_day(day_of_week)
    day_names = { 1 => "월", 2 => "화", 3 => "수", 4 => "목", 5 => "금" }

    # Random condition (simulate real life variance)
    condition = generate_random_condition

    # Skip workout sometimes (20% chance of rest day)
    if rand < 0.2
      puts "   #{day_names[day_of_week]}요일: 😴 휴식 (에너지 #{condition[:energy_level]}/5)"
      return
    end

    # Generate routine
    routine = generate_routine(day_of_week, condition)
    return unless routine

    @total_workouts += 1

    # Simulate workout completion (random performance)
    performance = simulate_workout_performance(routine)

    # Record workout
    record_workout(routine, performance)

    # Submit feedback
    feedback = generate_random_feedback(performance)
    submit_feedback(routine, feedback)

    # Log
    emoji = performance[:completion_rate] >= 0.8 ? "💪" : "😓"
    puts "   #{day_names[day_of_week]}요일: #{emoji} #{routine[:fitness_factor_korean]} - #{routine[:exercises].size}개 운동, 완료율 #{(performance[:completion_rate] * 100).round}%"

    # Store history
    @history << {
      week: @week,
      day: day_of_week,
      condition: condition,
      routine: routine,
      performance: performance,
      feedback: feedback
    }
  end

  def generate_random_condition
    # Simulate realistic condition patterns
    base_sleep_quality = 3 + rand(3) # 3-5
    base_energy = 3 + rand(3) # 3-5
    base_stress = 1 + rand(4) # 1-4
    base_motivation = 2 + rand(4) # 2-5
    base_time = [30, 45, 60, 75, 90].sample # Available time in minutes

    # Worse conditions on Monday (back from weekend) and Friday (accumulated fatigue)
    if @day == 1
      base_energy = [base_energy - 1, 1].max
    elsif @day == 5
      base_energy = [base_energy - 1, 1].max
      base_stress = [base_stress + 1, 5].min
    end

    # Occasional bad days (10% chance)
    if rand < 0.1
      base_sleep_quality = [1, 2].sample
      base_energy = [1, 2].sample
    end

    {
      energy_level: base_energy,
      stress_level: base_stress,
      sleep_quality: base_sleep_quality,
      motivation: base_motivation,
      available_time: base_time
    }
  end

  def generate_routine(day_of_week, condition)
    query = <<~GQL
      mutation GenerateAiRoutine($input: GenerateAiRoutineInput!) {
        generateAiRoutine(input: $input) {
          success
          error
          routine {
            routineId
            userLevel
            tier
            dayKorean
            fitnessFactor
            fitnessFactorKorean
            trainingMethod
            estimatedDurationMinutes
            exercises {
              order
              exerciseName
              targetMuscle
              sets
              reps
              restSeconds
            }
            notes
            condition {
              score
              status
              volumeModifier
              intensityModifier
            }
          }
        }
      }
    GQL

    result = graphql_request(query,
      input: {
        dayOfWeek: day_of_week,
        condition: {
          energyLevel: condition[:energy_level],
          stressLevel: condition[:stress_level],
          sleepQuality: condition[:sleep_quality],
          motivation: condition[:motivation],
          availableTime: condition[:available_time]
        }
      }
    )

    if result&.dig("data", "generateAiRoutine", "success")
      routine_data = result["data"]["generateAiRoutine"]["routine"]
      {
        routine_id: routine_data["routineId"],
        user_level: routine_data["userLevel"],
        tier: routine_data["tier"],
        fitness_factor: routine_data["fitnessFactor"],
        fitness_factor_korean: routine_data["fitnessFactorKorean"],
        training_method: routine_data["trainingMethod"],
        duration: routine_data["estimatedDurationMinutes"],
        exercises: routine_data["exercises"] || [],
        condition_score: routine_data.dig("condition", "score"),
        volume_modifier: routine_data.dig("condition", "volumeModifier")
      }
    else
      puts "   ❌ 루틴 생성 실패: #{result&.dig("data", "generateAiRoutine", "error")}"
      nil
    end
  end

  def simulate_workout_performance(routine)
    # Simulate realistic workout performance based on condition
    condition_score = routine[:condition_score].to_f
    condition_score = 3.0 if condition_score.zero?

    # Base completion rate based on condition
    base_rate = 0.6 + (condition_score / 5.0) * 0.4  # 0.6 - 1.0

    # Add some randomness
    completion_rate = [0.3, [1.0, base_rate + (rand - 0.5) * 0.3].min].max

    # Simulate actual reps completed for each exercise
    exercises_performance = routine[:exercises].map do |ex|
      target_reps = (ex["reps"].to_s.empty? ? 10 : ex["reps"].to_i)
      target_sets = (ex["sets"].to_s.empty? ? 3 : ex["sets"].to_i)

      actual_reps = (target_reps * completion_rate * (0.8 + rand * 0.4)).round
      actual_sets = (target_sets * completion_rate).ceil

      {
        exercise_name: ex["exerciseName"],
        target_sets: target_sets,
        target_reps: target_reps,
        actual_sets: actual_sets,
        actual_reps: actual_reps
      }
    end

    duration = routine[:duration].to_i
    duration = 45 if duration.zero?

    {
      completion_rate: completion_rate,
      exercises: exercises_performance,
      duration_minutes: (duration * (0.8 + rand * 0.4)).round
    }
  end

  def record_workout(routine, performance)
    query = <<~GQL
      mutation RecordWorkout($input: WorkoutRecordInput!) {
        recordWorkout(input: $input) {
          success
          error
          workoutRecord { id }
        }
      }
    GQL

    # Build exercises with proper format
    exercises = performance[:exercises].map do |ex|
      weight = rand(10..30).to_f
      completed_sets = (1..ex[:actual_sets]).map do |set_num|
        {
          setNumber: set_num,
          reps: ex[:actual_reps],
          weight: weight,
          rpe: rand(6..9)
        }
      end

      {
        exerciseName: ex[:exercise_name],
        targetMuscle: "CHEST", # Placeholder
        plannedSets: ex[:target_sets],
        completedSets: completed_sets
      }
    end

    # RPE based on completion rate
    rpe = if performance[:completion_rate] >= 0.9
            rand(4..6)
          elsif performance[:completion_rate] >= 0.7
            rand(6..8)
          else
            rand(8..10)
          end

    graphql_request(query,
      input: {
        routineId: routine[:routine_id],
        totalDuration: performance[:duration_minutes] * 60, # Convert to seconds
        perceivedExertion: rpe,
        completionStatus: "COMPLETED",
        exercises: exercises
      }
    )
  end

  def generate_random_feedback(performance)
    rating = if performance[:completion_rate] >= 0.9
               [4, 5].sample
             elsif performance[:completion_rate] >= 0.7
               [3, 4].sample
             else
               [2, 3].sample
             end

    difficulty = if performance[:completion_rate] >= 0.9
                   ["EASY", "JUST_RIGHT"].sample
                 elsif performance[:completion_rate] >= 0.6
                   ["JUST_RIGHT", "HARD"].sample
                 else
                   ["HARD", "TOO_HARD"].sample
                 end

    feedback_texts = [
      "오늘 운동 잘 했어요",
      "조금 힘들었어요",
      "다음엔 더 열심히 해볼게요",
      "컨디션이 별로였어요",
      "오늘은 최고였어요!",
      "무게를 늘려야 할 것 같아요",
      "휴식이 부족했어요"
    ]

    {
      rating: rating,
      difficulty: difficulty,
      feedback: feedback_texts.sample
    }
  end

  def submit_feedback(routine, feedback)
    query = <<~GQL
      mutation SubmitFeedback($input: SubmitFeedbackInput!) {
        submitFeedback(input: $input) {
          success
        }
      }
    GQL

    graphql_request(query,
      input: {
        routineId: routine[:routine_id],
        rating: feedback[:rating],
        difficulty: feedback[:difficulty],
        feedback: feedback[:feedback]
      }
    )
  end

  def check_and_do_level_test
    # Check eligibility
    query = <<~GQL
      query {
        checkLevelTestEligibility {
          eligible
          reason
          currentLevel
          targetLevel
          currentWorkouts
          requiredWorkouts
        }
      }
    GQL

    result = graphql_request(query)
    eligibility = result&.dig("data", "checkLevelTestEligibility")

    return unless eligibility

    if eligibility["eligible"]
      puts
      puts "   🎯 승급 시험 자격 획득! (#{eligibility["currentWorkouts"]}/#{eligibility["requiredWorkouts"]} 운동)"
      puts "   📝 레벨 #{eligibility["currentLevel"]} → #{eligibility["targetLevel"]} 승급 시험 시작..."

      do_level_test(eligibility["currentLevel"], eligibility["targetLevel"])
    else
      puts "   📊 승급 시험: #{eligibility["reason"]} (#{eligibility["currentWorkouts"] || 0}/#{eligibility["requiredWorkouts"] || 10})"
    end
  end

  def do_level_test(current_level, target_level)
    # Start level test
    start_query = <<~GQL
      mutation {
        startLevelTest(input: {}) {
          success
          error
          test {
            testId
            currentLevel
            targetLevel
            exercises {
              exerciseType
              targetWeightKg
              targetReps
            }
          }
        }
      }
    GQL

    result = graphql_request(start_query)
    test = result&.dig("data", "startLevelTest", "test")

    return unless test

    # Simulate test results (70% chance of passing)
    passed = rand < 0.7

    exercises = test["exercises"].map do |ex|
      target_weight = ex["targetWeightKg"]
      target_reps = ex["targetReps"]

      if passed
        # Pass: achieve or exceed target
        {
          exerciseType: ex["exerciseType"],
          weightKg: target_weight + rand(-2..5),
          reps: target_reps + rand(0..2)
        }
      else
        # Fail: fall short
        {
          exerciseType: ex["exerciseType"],
          weightKg: target_weight - rand(5..15),
          reps: [1, target_reps - rand(2..4)].max
        }
      end
    end

    # Submit results
    submit_query = <<~GQL
      mutation SubmitLevelTestResult($input: SubmitLevelTestResultInput!) {
        submitLevelTestResult(input: $input) {
          success
          passed
          newLevel
          feedback
          nextSteps
        }
      }
    GQL

    result = graphql_request(submit_query,
      input: {
        testId: test["testId"],
        exercises: exercises
      }
    )

    submission = result&.dig("data", "submitLevelTestResult")

    if submission&.dig("passed")
      @current_level = submission["newLevel"]
      puts "   🎉 승급 성공! 새로운 레벨: #{@current_level}"
    else
      puts "   😢 승급 실패. 다음에 다시 도전하세요!"
      puts "   💡 #{submission&.dig("feedback")&.first}"
    end
  end

  def print_summary
    puts
    puts "=" * 60
    puts "📊 12주 시뮬레이션 결과 요약"
    puts "=" * 60
    puts
    puts "총 운동 횟수: #{@total_workouts}회"
    puts "최종 레벨: #{@current_level}"
    puts

    # Analyze by week
    puts "주차별 통계:"
    (1..12).each do |week|
      week_data = @history.select { |h| h[:week] == week }
      next if week_data.empty?

      avg_completion = week_data.map { |h| h[:performance][:completion_rate] }.sum / week_data.size
      avg_condition = week_data.map { |h|
        c = h[:condition]
        (c[:energy_level] + (6 - c[:stress_level]) + c[:sleep_quality] + c[:motivation]) / 4.0
      }.sum / week_data.size

      puts "  Week #{week.to_s.rjust(2)}: #{week_data.size}회 운동, 평균 완료율 #{(avg_completion * 100).round}%, 평균 컨디션 #{avg_condition.round(1)}/5"
    end

    puts
    puts "체력요인별 분포:"
    factor_counts = @history.group_by { |h| h[:routine][:fitness_factor_korean] }
    factor_counts.each do |factor, data|
      puts "  #{factor}: #{data.size}회"
    end

    puts
    puts "시뮬레이션 완료! 🏁"
  end
end

# Run simulation
simulator = UserSimulator.new
simulator.run(weeks: 12)
