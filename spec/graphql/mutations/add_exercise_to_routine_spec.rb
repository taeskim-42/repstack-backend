# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Mutations::AddExerciseToRoutine, type: :graphql do
  let(:user) { create(:user) }
  let(:other_user) { create(:user) }

  let(:mutation) do
    <<~GQL
      mutation AddExerciseToRoutine(
        $routineId: ID!
        $exerciseName: String
        $sets: Int
        $reps: Int
        $weight: Float
        $targetMuscle: String
        $orderIndex: Int
      ) {
        addExerciseToRoutine(input: {
          routineId: $routineId
          exerciseName: $exerciseName
          sets: $sets
          reps: $reps
          weight: $weight
          targetMuscle: $targetMuscle
          orderIndex: $orderIndex
        }) {
          success
          routine {
            id
            routineExercises {
              exerciseName
              sets
              reps
              orderIndex
            }
          }
          addedExercise {
            exerciseName
            sets
            reps
            weight
            targetMuscle
            orderIndex
          }
          error
        }
      }
    GQL
  end

  def execute_mutation(variables = {}, current_user: user)
    RepstackBackendSchema.execute(
      mutation,
      variables: variables,
      context: { current_user: current_user }
    )
  end

  describe 'when authenticated' do
    let!(:routine) do
      create(:workout_routine, user: user, is_completed: false)
    end

    context 'with valid exercise name' do
      it 'adds exercise to routine' do
        result = execute_mutation({
                                    routineId: routine.id.to_s,
                                    exerciseName: '벤치프레스',
                                    sets: 4,
                                    reps: 10,
                                    weight: 60.0
                                  })

        data = result['data']['addExerciseToRoutine']
        expect(data['success']).to be true
        expect(data['addedExercise']['exerciseName']).to eq('벤치프레스')
        expect(data['addedExercise']['sets']).to eq(4)
        expect(data['addedExercise']['reps']).to eq(10)
        expect(data['addedExercise']['weight']).to eq(60.0)
      end

      it 'infers target muscle from exercise name' do
        result = execute_mutation({
                                    routineId: routine.id.to_s,
                                    exerciseName: '풀업'
                                  })

        data = result['data']['addExerciseToRoutine']
        expect(data['addedExercise']['targetMuscle']).to eq('back')
      end

      it 'uses default sets and reps' do
        result = execute_mutation({
                                    routineId: routine.id.to_s,
                                    exerciseName: '스쿼트'
                                  })

        data = result['data']['addExerciseToRoutine']
        expect(data['addedExercise']['sets']).to eq(3) # default
        expect(data['addedExercise']['reps']).to eq(10) # default
      end
    end

    context 'with order_index specified' do
      before do
        routine.routine_exercises.create!(exercise_name: '기존운동1', order_index: 0, sets: 3, reps: 10)
        routine.routine_exercises.create!(exercise_name: '기존운동2', order_index: 1, sets: 3, reps: 10)
      end

      it 'inserts at specified position and reorders' do
        result = execute_mutation({
                                    routineId: routine.id.to_s,
                                    exerciseName: '새운동',
                                    orderIndex: 1
                                  })

        data = result['data']['addExerciseToRoutine']
        expect(data['success']).to be true
        expect(data['addedExercise']['orderIndex']).to eq(1)
      end
    end

    context 'with completed routine' do
      let!(:completed_routine) do
        create(:workout_routine, user: user, is_completed: true)
      end

      it 'returns error' do
        result = execute_mutation({
                                    routineId: completed_routine.id.to_s,
                                    exerciseName: '벤치프레스'
                                  })

        data = result['data']['addExerciseToRoutine']
        expect(data['success']).to be false
        expect(data['error']).to include('완료된 루틴')
      end
    end

    context 'with non-existent routine' do
      it 'returns error' do
        result = execute_mutation({
                                    routineId: '99999',
                                    exerciseName: '벤치프레스'
                                  })

        data = result['data']['addExerciseToRoutine']
        expect(data['success']).to be false
        expect(data['error']).to include('찾을 수 없습니다')
      end
    end

    context 'with other user routine' do
      let!(:other_routine) do
        create(:workout_routine, user: other_user, is_completed: false)
      end

      it 'returns error' do
        result = execute_mutation({
                                    routineId: other_routine.id.to_s,
                                    exerciseName: '벤치프레스'
                                  })

        data = result['data']['addExerciseToRoutine']
        expect(data['success']).to be false
        expect(data['error']).to include('찾을 수 없습니다')
      end
    end

    context 'without exercise_id or exercise_name' do
      it 'returns error' do
        result = execute_mutation({ routineId: routine.id.to_s })

        data = result['data']['addExerciseToRoutine']
        expect(data['success']).to be false
        expect(data['error']).to include('exercise_id 또는 exercise_name')
      end
    end
  end

  describe 'when not authenticated' do
    it 'returns error' do
      result = execute_mutation({ routineId: '1', exerciseName: '벤치프레스' }, current_user: nil)

      expect(result['errors']).to be_present
      expect(result['errors'].first['message']).to include('Authentication required')
    end
  end
end
