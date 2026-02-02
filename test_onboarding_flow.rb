# frozen_string_literal: true

# Test full onboarding flow 100 times
# Run with: rbenv exec bundle exec rails runner test_onboarding_flow.rb

$stdout.sync = true
require 'json'

ITERATIONS = 100
RESULTS = []

def run_onboarding_flow(iteration)
  result = {
    iteration: iteration,
    user_id: nil,
    steps: {},
    success: false,
    error: nil,
    routine_exercises_count: 0
  }
  
  begin
    # Step 1: Create fresh user
    timestamp = Time.current.to_i
    user = User.create!(
      email: "test_onboarding_#{iteration}_#{timestamp}@test.com",
      name: "TestUser#{iteration}",
      apple_user_id: "test_#{SecureRandom.hex(8)}"
    )
    result[:user_id] = user.id
    
    # Create profile with clean state
    profile = user.create_user_profile!(
      level_assessed_at: nil,
      fitness_factors: {}
    )
    result[:steps][:user_created] = true
    
    # Step 2: Form onboarding (UpdateUserProfile equivalent)
    profile.update!(
      height: 175.0,
      weight: 70.0,
      current_level: 'beginner',
      fitness_goal: '근비대',
      form_onboarding_completed_at: Time.current
    )
    result[:steps][:form_completed] = true
    
    # Step 3: AI consultation (LevelAssessmentService)
    # Simulate conversation turns
    chat_messages = [
      "안녕하세요",
      "주 4회, 1시간 정도 가능해요",
      "헬스장에서 해요",
      "부상은 없어요",
      "어깨랑 등을 키우고 싶어요",
      "특별히 없어요",
      "루틴 만들어주세요"
    ]
    
    chat_messages.each_with_index do |msg, idx|
      chat_result = ChatService.process(
        user: user,
        message: msg,
        routine_id: nil,
        session_id: "test_session_#{iteration}"
      )
      
      # Check if assessment completed or routine generated
      if chat_result[:intent] == 'LEVEL_ASSESSMENT' && chat_result[:data]&.dig(:is_complete)
        result[:steps][:consultation_completed] = true
      end
      
      if chat_result[:intent] == 'WELCOME_WITH_ROUTINE' || chat_result[:intent] == 'GENERATE_ROUTINE'
        result[:steps][:routine_generated] = true
        routine_data = chat_result[:data]&.dig(:routine)
        if routine_data
          exercises = routine_data[:exercises] || routine_data['exercises'] || []
          result[:routine_exercises_count] = exercises.count
        end
        break
      end
    end
    
    # Check final state
    profile.reload
    result[:steps][:onboarding_completed_at] = profile.onboarding_completed_at.present?
    result[:steps][:has_routines] = user.workout_routines.exists?
    
    if result[:steps][:has_routines]
      routine = user.workout_routines.last
      result[:routine_exercises_count] = routine.routine_exercises.count if result[:routine_exercises_count] == 0
    end
    
    result[:success] = result[:steps][:routine_generated] || result[:steps][:has_routines]
    
  rescue StandardError => e
    result[:error] = "#{e.class}: #{e.message}"
    result[:success] = false
  ensure
    # Cleanup
    if user&.persisted?
      user.workout_routines.destroy_all rescue nil
      user.user_profile&.destroy rescue nil
      user.destroy rescue nil
    end
  end
  
  result
end

puts "=" * 60
puts "Starting Onboarding Flow Test (#{ITERATIONS} iterations)"
puts "=" * 60
puts

start_time = Time.current

ITERATIONS.times do |i|
  result = run_onboarding_flow(i + 1)
  RESULTS << result
  
  status = result[:success] ? "✓" : "✗"
  exercises = result[:routine_exercises_count]
  error_msg = result[:error] ? " - #{result[:error][0..50]}" : ""
  
  puts "Run #{i + 1}: #{status} | exercises=#{exercises}#{error_msg}"
  
  # Progress indicator every 10 runs
  if (i + 1) % 10 == 0
    success_rate = RESULTS.count { |r| r[:success] } * 100.0 / RESULTS.count
    puts "  [Progress: #{i + 1}/#{ITERATIONS}, Success: #{success_rate.round(1)}%]"
  end
end

elapsed = Time.current - start_time

# Summary
puts
puts "=" * 60
puts "SUMMARY"
puts "=" * 60

total = RESULTS.count
successes = RESULTS.count { |r| r[:success] }
failures = total - successes

puts "Total: #{total}"
puts "Successes: #{successes} (#{(successes * 100.0 / total).round(1)}%)"
puts "Failures: #{failures} (#{(failures * 100.0 / total).round(1)}%)"
puts "Time: #{elapsed.round(1)}s (avg: #{(elapsed / total).round(2)}s per run)"
puts

# Exercise count distribution
exercise_counts = RESULTS.select { |r| r[:success] }.map { |r| r[:routine_exercises_count] }
if exercise_counts.any?
  puts "Exercise counts in successful routines:"
  puts "  Min: #{exercise_counts.min}"
  puts "  Max: #{exercise_counts.max}"
  puts "  Avg: #{(exercise_counts.sum.to_f / exercise_counts.count).round(1)}"
  puts "  Distribution: #{exercise_counts.tally.sort.to_h}"
end

# List failures
if failures > 0
  puts
  puts "FAILURES:"
  RESULTS.select { |r| !r[:success] }.each do |r|
    puts "  Run #{r[:iteration]}: #{r[:error] || 'Unknown error'}"
    puts "    Steps completed: #{r[:steps].select { |k, v| v }.keys.join(', ')}"
  end
end
