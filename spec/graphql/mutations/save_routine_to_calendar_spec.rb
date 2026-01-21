# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Mutations::SaveRoutineToCalendar, type: :graphql do
  let(:user) { create(:user) }

  let(:mutation) do
    <<~GQL
      mutation SaveRoutineToCalendar(
        $dayOfWeek: Int!
        $weekOffset: Int
        $estimatedDuration: Int
        $exercises: [RoutineExerciseInput!]!
      ) {
        saveRoutineToCalendar(input: {
          dayOfWeek: $dayOfWeek
          weekOffset: $weekOffset
          estimatedDuration: $estimatedDuration
          exercises: $exercises
        }) {
          success
          savedRoutine {
            id
            dayOfWeek
            weekStartDate
            routine {
              id
              dayOfWeek
              estimatedDuration
              routineExercises {
                exerciseName
                sets
                reps
                weight
                orderIndex
              }
            }
          }
          error
        }
      }
    GQL
  end

  let(:valid_exercises) do
    [
      {
        exerciseName: '벤치프레스',
        orderIndex: 0,
        sets: 4,
        reps: 10,
        weight: 60.0,
        targetMuscle: 'chest'
      },
      {
        exerciseName: '스쿼트',
        orderIndex: 1,
        sets: 4,
        reps: 8,
        weight: 80.0,
        targetMuscle: 'legs'
      }
    ]
  end

  def execute_mutation(variables = {}, current_user: user)
    RepstackBackendSchema.execute(
      mutation,
      variables: variables,
      context: { current_user: current_user }
    )
  end

  describe 'when authenticated' do
    before do
      create(:user_profile, user: user, current_level: 'intermediate', week_number: 2)
    end

    context 'with valid input' do
      it 'creates routine with exercises' do
        result = execute_mutation({
                                    dayOfWeek: 1, # Monday
                                    exercises: valid_exercises
                                  })

        data = result['data']['saveRoutineToCalendar']
        expect(data['success']).to be true
        expect(data['savedRoutine']['dayOfWeek']).to eq(1)
        expect(data['savedRoutine']['routine']['routineExercises'].count).to eq(2)
      end

      it 'saves estimated duration' do
        result = execute_mutation({
                                    dayOfWeek: 2,
                                    estimatedDuration: 45,
                                    exercises: valid_exercises
                                  })

        data = result['data']['saveRoutineToCalendar']
        expect(data['savedRoutine']['routine']['estimatedDuration']).to eq(45)
      end

      it 'supports week offset for future weeks' do
        result = execute_mutation({
                                    dayOfWeek: 3, # Wednesday
                                    weekOffset: 1, # Next week
                                    exercises: valid_exercises
                                  })

        data = result['data']['saveRoutineToCalendar']
        expect(data['success']).to be true

        # week_start_date should be next week's Monday
        expected_week_start = Date.current.beginning_of_week + 7.days
        expect(data['savedRoutine']['weekStartDate']).to eq(expected_week_start.strftime('%Y-%m-%d'))
      end
    end

    context 'with invalid day_of_week' do
      it 'returns error for day < 1' do
        result = execute_mutation({
                                    dayOfWeek: 0,
                                    exercises: valid_exercises
                                  })

        data = result['data']['saveRoutineToCalendar']
        expect(data['success']).to be false
        expect(data['error']).to include('1(월요일)부터 7(일요일)')
      end

      it 'returns error for day > 7' do
        result = execute_mutation({
                                    dayOfWeek: 8,
                                    exercises: valid_exercises
                                  })

        data = result['data']['saveRoutineToCalendar']
        expect(data['success']).to be false
        expect(data['error']).to include('1(월요일)부터 7(일요일)')
      end
    end

    context 'with existing routine on same day' do
      before do
        create(:workout_routine,
               user: user,
               day_of_week: 'Monday',
               day_number: 1,
               is_completed: false,
               generated_at: Time.current)
      end

      it 'returns error' do
        result = execute_mutation({
                                    dayOfWeek: 1,
                                    exercises: valid_exercises
                                  })

        data = result['data']['saveRoutineToCalendar']
        expect(data['success']).to be false
        expect(data['error']).to include('해당 요일에 이미 루틴이 있습니다')
      end
    end

    context 'with completed routine on same day' do
      before do
        create(:workout_routine,
               user: user,
               day_of_week: 'Monday',
               day_number: 1,
               is_completed: true,
               generated_at: Time.current)
      end

      it 'allows creating new routine' do
        result = execute_mutation({
                                    dayOfWeek: 1,
                                    exercises: valid_exercises
                                  })

        data = result['data']['saveRoutineToCalendar']
        expect(data['success']).to be true
      end
    end

    context 'with old routine from previous week' do
      before do
        create(:workout_routine,
               user: user,
               day_of_week: 'Monday',
               day_number: 1,
               is_completed: false,
               generated_at: 2.weeks.ago)
      end

      it 'allows creating new routine' do
        result = execute_mutation({
                                    dayOfWeek: 1,
                                    exercises: valid_exercises
                                  })

        data = result['data']['saveRoutineToCalendar']
        expect(data['success']).to be true
      end
    end

    context 'preserves exercise details' do
      let(:detailed_exercises) do
        [
          {
            exerciseName: '벤치프레스',
            orderIndex: 0,
            sets: 4,
            reps: 10,
            weight: 60.0,
            weightDescription: '60kg',
            targetMuscle: 'chest',
            bpm: 60,
            restDurationSeconds: 90,
            rangeOfMotion: '가슴까지 내리기',
            howTo: '바벨을 가슴까지 천천히 내린다',
            purpose: '대흉근 발달'
          }
        ]
      end

      it 'saves all exercise fields' do
        result = execute_mutation({
                                    dayOfWeek: 4,
                                    exercises: detailed_exercises
                                  })

        data = result['data']['saveRoutineToCalendar']
        expect(data['success']).to be true

        # Verify in database
        routine = WorkoutRoutine.find(data['savedRoutine']['id'])
        exercise = routine.routine_exercises.first
        expect(exercise.weight_description).to eq('60kg')
        expect(exercise.bpm).to eq(60)
        expect(exercise.rest_duration_seconds).to eq(90)
        expect(exercise.range_of_motion).to eq('가슴까지 내리기')
        expect(exercise.how_to).to eq('바벨을 가슴까지 천천히 내린다')
        expect(exercise.purpose).to eq('대흉근 발달')
      end
    end
  end

  describe 'when not authenticated' do
    it 'returns error' do
      result = execute_mutation({ dayOfWeek: 1, exercises: valid_exercises }, current_user: nil)

      expect(result['errors']).to be_present
      expect(result['errors'].first['message']).to include('Authentication required')
    end
  end
end
