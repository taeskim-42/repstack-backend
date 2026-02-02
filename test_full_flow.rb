# frozen_string_literal: true

$stdout.sync = true

# Test complete onboarding flow via API simulation
# Run with: rbenv exec bundle exec rails runner test_full_flow.rb

puts "=" * 60
puts "Full Onboarding Flow Test"
puts "=" * 60
puts

# Step 1: Create fresh user (simulating DevSignInFresh)
puts "[Step 1] Creating fresh user..."
timestamp = Time.current.to_i
user = User.create!(
  email: "fulltest_#{timestamp}@test.com",
  name: "FullFlowTest",
  apple_user_id: "test_#{SecureRandom.hex(8)}"
)
puts "  ✓ User created: #{user.id} (#{user.email})"

# Create profile with clean state
profile = user.create_user_profile!(
  level_assessed_at: nil,
  fitness_factors: {}
)
puts "  ✓ Profile created"

# Step 2: Form data input (simulating UpdateUserProfile)
puts "\n[Step 2] Filling form data..."
profile.update!(
  height: 175.0,
  weight: 70.0,
  current_level: 'beginner',
  fitness_goal: '근비대',
  form_onboarding_completed_at: Time.current
)
puts "  ✓ Form data saved: height=175, weight=70, level=beginner, goal=근비대"

# Check state
puts "  form_onboarding_completed_at: #{profile.form_onboarding_completed_at.present? ? 'SET' : 'nil'}"
puts "  onboarding_completed_at: #{profile.onboarding_completed_at.present? ? 'SET' : 'nil'}"
puts "  needs_assessment: #{AiTrainer::LevelAssessmentService.needs_assessment?(user)}"

# Step 3: AI consultation (Chat mutation with LevelAssessmentService)
puts "\n[Step 3] Starting AI consultation..."
session_id = "test_session_#{timestamp}"

consultation_messages = [
  "안녕하세요",
  "주 4회, 1시간 정도 가능해요",
  "헬스장에서 해요", 
  "부상은 없어요",
  "어깨랑 등을 키우고 싶어요",
  "특별히 없어요",
  "루틴 만들어주세요"
]

consultation_messages.each_with_index do |msg, idx|
  puts "\n  [#{idx + 1}/#{consultation_messages.length}] User: '#{msg}'"
  
  result = ChatService.process(
    user: user,
    message: msg,
    routine_id: nil,
    session_id: session_id
  )
  
  intent = result[:intent]
  is_complete = result[:data]&.dig(:is_complete)
  
  puts "  Intent: #{intent}"
  puts "  Bot: #{result[:message]&.first(100)}..."
  
  if intent == 'WELCOME_WITH_ROUTINE' || intent == 'GENERATE_ROUTINE'
    puts "\n  🎉 Routine generated!"
    routine_data = result[:data]&.dig(:routine)
    if routine_data
      exercises = routine_data[:exercises] || routine_data['exercises'] || []
      puts "  Exercises count: #{exercises.count}"
      exercises.first(3).each_with_index do |ex, i|
        name = ex[:exercise_name] || ex['exercise_name']
        puts "    #{i+1}. #{name}"
      end
    end
    break
  end
  
  if is_complete
    puts "  ✓ Consultation completed!"
  end
end

# Check final state
puts "\n[Step 4] Checking final state..."
profile.reload
user.reload

puts "  onboarding_completed_at: #{profile.onboarding_completed_at.present? ? 'SET' : 'nil'}"
puts "  numeric_level: #{profile.numeric_level}"
puts "  current_level (tier): #{profile.current_level}"

routines = user.workout_routines.reload
puts "  workout_routines count: #{routines.count}"

if routines.any?
  routine = routines.last
  puts "\n  Last routine:"
  puts "    ID: #{routine.id}"
  puts "    Exercises: #{routine.routine_exercises.count}"
  routine.routine_exercises.order(:order_index).each_with_index do |ex, i|
    puts "      #{i+1}. #{ex.exercise_name} (#{ex.sets}x#{ex.reps})"
  end
end

# Cleanup
puts "\n[Cleanup] Deleting test data..."
user.workout_routines.destroy_all
OnboardingAnalytics.where(user: user).destroy_all
user.user_profile&.destroy
user.destroy
puts "  ✓ Cleaned up"

puts "\n" + "=" * 60
puts "Test Complete!"
puts "=" * 60
