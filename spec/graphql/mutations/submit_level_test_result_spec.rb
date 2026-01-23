# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Mutations::SubmitLevelTestResult, type: :graphql do
  let(:user) { create(:user) }
  let!(:profile) { create(:user_profile, user: user, numeric_level: 1) }

  let(:mutation) do
    <<~GQL
      mutation SubmitLevelTestResult($testId: String!, $exercises: [LevelTestExerciseResultInput!]!) {
        submitLevelTestResult(input: { testId: $testId, exercises: $exercises }) {
          success
          passed
          newLevel
          feedback
          nextSteps
          error
          results {
            passedExercises {
              exercise
              required
              achieved
              status
            }
            failedExercises {
              exercise
              required
              achieved
              status
              gap
            }
            totalExercises
            passRate
          }
        }
      }
    GQL
  end

  let(:exercises_input) do
    [
      { exerciseType: 'bench', weightKg: 70.0, reps: 8 },
      { exerciseType: 'squat', weightKg: 90.0, reps: 8 },
      { exerciseType: 'deadlift', weightKg: 110.0, reps: 8 }
    ]
  end

  describe 'when authenticated' do
    context 'when test passes' do
      before do
        allow(AiTrainer).to receive(:evaluate_level_test).and_return({
          success: true,
          passed: true,
          new_level: 2,
          results: {
            passed_exercises: [
              { exercise: 'bench', required: 80.0, achieved: 87.5, status: 'passed' },
              { exercise: 'squat', required: 100.0, achieved: 112.5, status: 'passed' },
              { exercise: 'deadlift', required: 120.0, achieved: 137.5, status: 'passed' }
            ],
            failed_exercises: [],
            total_exercises: 3,
            pass_rate: 100.0
          },
          feedback: ['축하합니다! 모든 테스트를 통과했습니다.'],
          next_steps: ['레벨 2 프로그램을 시작하세요.']
        })
      end

      it 'returns success and updates user profile' do
        result = execute_graphql(
          query: mutation,
          variables: { testId: 'test-123', exercises: exercises_input },
          context: { current_user: user }
        )

        data = result['data']['submitLevelTestResult']
        expect(data['success']).to be true
        expect(data['passed']).to be true
        expect(data['newLevel']).to eq(2)
        expect(data['feedback']).to include('축하합니다! 모든 테스트를 통과했습니다.')
        expect(data['error']).to be_nil

        # Check that profile was updated
        expect(profile.reload.numeric_level).to eq(2)
        expect(profile.last_level_test_at).to be_present
      end

      it 'returns exercise results' do
        result = execute_graphql(
          query: mutation,
          variables: { testId: 'test-123', exercises: exercises_input },
          context: { current_user: user }
        )

        results = result['data']['submitLevelTestResult']['results']
        expect(results['totalExercises']).to eq(3)
        expect(results['passRate']).to eq(100.0)
        expect(results['passedExercises'].length).to eq(3)

        bench = results['passedExercises'].find { |e| e['exercise'] == 'bench' }
        expect(bench['status']).to eq('passed')
        expect(bench['achieved']).to eq(87.5)
      end
    end

    context 'when test fails' do
      before do
        allow(AiTrainer).to receive(:evaluate_level_test).and_return({
          success: true,
          passed: false,
          new_level: 1,
          results: {
            passed_exercises: [],
            failed_exercises: [
              { exercise: 'bench', required: 80.0, achieved: 56.0, status: 'failed', gap: 24.0 }
            ],
            total_exercises: 1,
            pass_rate: 0.0
          },
          feedback: ['기준에 도달하지 못했습니다.'],
          next_steps: ['더 훈련 후 다시 도전하세요.']
        })
      end

      it 'returns failure without updating profile' do
        original_level = profile.numeric_level

        result = execute_graphql(
          query: mutation,
          variables: { testId: 'test-456', exercises: exercises_input },
          context: { current_user: user }
        )

        data = result['data']['submitLevelTestResult']
        expect(data['success']).to be true
        expect(data['passed']).to be false
        expect(data['newLevel']).to eq(1)
        expect(data['feedback']).to include('기준에 도달하지 못했습니다.')

        # Profile should not be updated
        expect(profile.reload.numeric_level).to eq(original_level)
      end
    end

    context 'when evaluation fails' do
      before do
        allow(AiTrainer).to receive(:evaluate_level_test).and_return({
          success: false,
          error: '평가 중 오류가 발생했습니다.'
        })
      end

      it 'returns error response' do
        result = execute_graphql(
          query: mutation,
          variables: { testId: 'test-789', exercises: exercises_input },
          context: { current_user: user }
        )

        data = result['data']['submitLevelTestResult']
        expect(data['success']).to be false
        expect(data['passed']).to be_nil
        expect(data['newLevel']).to be_nil
        expect(data['error']).to eq('평가 중 오류가 발생했습니다.')
      end
    end

    context 'without user profile' do
      let(:user_without_profile) { create(:user) }

      before do
        allow(AiTrainer).to receive(:evaluate_level_test).and_return({
          success: true,
          passed: true,
          new_level: 2,
          results: {
            passed_exercises: [],
            failed_exercises: [],
            total_exercises: 0,
            pass_rate: 0.0
          },
          feedback: [],
          next_steps: []
        })
      end

      it 'succeeds without updating profile' do
        result = execute_graphql(
          query: mutation,
          variables: { testId: 'test-000', exercises: exercises_input },
          context: { current_user: user_without_profile }
        )

        data = result['data']['submitLevelTestResult']
        expect(data['success']).to be true
        expect(data['passed']).to be true
      end
    end
  end

  describe 'when not authenticated' do
    it 'returns authentication error' do
      result = execute_graphql(
        query: mutation,
        variables: { testId: 'test-123', exercises: exercises_input },
        context: { current_user: nil }
      )

      expect(result['errors']).to be_present
    end
  end
end
