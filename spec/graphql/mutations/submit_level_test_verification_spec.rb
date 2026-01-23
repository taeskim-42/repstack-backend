# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Mutations::SubmitLevelTestVerification, type: :graphql do
  let(:user) { create(:user) }
  let!(:profile) { create(:user_profile, user: user, numeric_level: 3, height: 175, weight: 70) }

  let(:mutation) do
    <<~GQL
      mutation SubmitLevelTestVerification($input: SubmitLevelTestVerificationInput!) {
        submitLevelTestVerification(input: $input) {
          success
          message
          errors
          verification {
            testId
            status
            currentLevel
            targetLevel
            passed
            newLevel
            aiFeedback
            exercises {
              exerciseType
              weightKg
              passed
              poseScore
              formIssues
            }
          }
        }
      }
    GQL
  end

  before do
    allow(AiTrainer::LlmGateway).to receive(:chat).and_return({
      success: true,
      content: '축하합니다! 열심히 하셨네요.',
      model: 'mock'
    })
  end

  describe 'when authenticated' do
    context 'with valid passing exercises' do
      let(:variables) do
        {
          input: {
            input: {
              exercises: [
                { exerciseType: 'bench', weightKg: 70.0, poseScore: 85.0, formIssues: [] },
                { exerciseType: 'squat', weightKg: 90.0, poseScore: 80.0, formIssues: [] },
                { exerciseType: 'deadlift', weightKg: 120.0, poseScore: 82.0, formIssues: [] }
              ]
            }
          }
        }
      end

      it 'creates verification and passes' do
        result = execute_graphql(query: mutation, variables: variables, context: { current_user: user })

        # Debug: Print errors if data is nil
        if result['data'].nil? || result['errors'].present?
          puts "GraphQL Errors: #{result['errors'].inspect}"
        end

        expect(result['data']).not_to be_nil, "Expected data but got errors: #{result['errors']}"
        data = result['data']['submitLevelTestVerification']
        expect(data['success']).to be true
        expect(data['verification']['passed']).to be true
        expect(data['verification']['newLevel']).to eq(4)
        expect(data['verification']['status']).to eq('passed')
      end

      it 'updates user profile level' do
        execute_graphql(query: mutation, variables: variables, context: { current_user: user })

        profile.reload
        expect(profile.numeric_level).to eq(4)
      end

      it 'creates level_test_verification record' do
        expect {
          execute_graphql(query: mutation, variables: variables, context: { current_user: user })
        }.to change { LevelTestVerification.count }.by(1)
      end

      it 'returns exercise results' do
        result = execute_graphql(query: mutation, variables: variables, context: { current_user: user })

        exercises = result['data']['submitLevelTestVerification']['verification']['exercises']
        expect(exercises.length).to eq(3)
        expect(exercises.map { |e| e['exerciseType'] }).to contain_exactly('bench', 'squat', 'deadlift')
      end
    end

    context 'with failing exercises (insufficient weight)' do
      let(:variables) do
        {
          input: {
            input: {
              exercises: [
                { exerciseType: 'bench', weightKg: 40.0, poseScore: 85.0, formIssues: [] },
                { exerciseType: 'squat', weightKg: 50.0, poseScore: 80.0, formIssues: [] },
                { exerciseType: 'deadlift', weightKg: 60.0, poseScore: 82.0, formIssues: [] }
              ]
            }
          }
        }
      end

      it 'creates verification and fails' do
        result = execute_graphql(query: mutation, variables: variables, context: { current_user: user })

        data = result['data']['submitLevelTestVerification']
        expect(data['success']).to be false
        expect(data['verification']['passed']).to be false
        expect(data['verification']['newLevel']).to eq(3)
        expect(data['verification']['status']).to eq('failed')
      end

      it 'does not update user profile level' do
        execute_graphql(query: mutation, variables: variables, context: { current_user: user })

        profile.reload
        expect(profile.numeric_level).to eq(3)
      end

      it 'includes form issues for failed exercises' do
        result = execute_graphql(query: mutation, variables: variables, context: { current_user: user })

        exercises = result['data']['submitLevelTestVerification']['verification']['exercises']
        bench = exercises.find { |e| e['exerciseType'] == 'bench' }
        expect(bench['passed']).to be false
        expect(bench['formIssues']).to include(/무게 부족/)
      end
    end

    context 'with low pose score' do
      let(:variables) do
        {
          input: {
            input: {
              exercises: [
                { exerciseType: 'bench', weightKg: 70.0, poseScore: 50.0, formIssues: [] }
              ]
            }
          }
        }
      end

      it 'fails due to low pose score' do
        result = execute_graphql(query: mutation, variables: variables, context: { current_user: user })

        exercises = result['data']['submitLevelTestVerification']['verification']['exercises']
        bench = exercises.find { |e| e['exerciseType'] == 'bench' }
        expect(bench['passed']).to be false
        expect(bench['formIssues']).to include(/자세 점수 미달/)
      end
    end

    context 'with form issues from CoreML' do
      let(:variables) do
        {
          input: {
            input: {
              exercises: [
                { exerciseType: 'squat', weightKg: 90.0, poseScore: 85.0, formIssues: ['깊이 부족', '무릎 위치 불량'] }
              ]
            }
          }
        }
      end

      it 'fails due to form issues' do
        result = execute_graphql(query: mutation, variables: variables, context: { current_user: user })

        exercises = result['data']['submitLevelTestVerification']['verification']['exercises']
        squat = exercises.find { |e| e['exerciseType'] == 'squat' }
        expect(squat['passed']).to be false
        expect(squat['formIssues']).to include('깊이 부족')
      end
    end

    context 'with custom test_id' do
      let(:variables) do
        {
          input: {
            input: {
              testId: 'CUSTOM-TEST-123',
              exercises: [
                { exerciseType: 'bench', weightKg: 70.0, poseScore: 85.0, formIssues: [] }
              ]
            }
          }
        }
      end

      it 'uses provided test_id' do
        result = execute_graphql(query: mutation, variables: variables, context: { current_user: user })

        expect(result['data']['submitLevelTestVerification']['verification']['testId']).to eq('CUSTOM-TEST-123')
      end
    end

    context 'when at max level' do
      before { profile.update!(numeric_level: 8) }

      let(:variables) do
        {
          input: {
            input: {
              exercises: [
                { exerciseType: 'bench', weightKg: 100.0, poseScore: 90.0, formIssues: [] }
              ]
            }
          }
        }
      end

      it 'returns error' do
        result = execute_graphql(query: mutation, variables: variables, context: { current_user: user })

        data = result['data']['submitLevelTestVerification']
        expect(data['success']).to be false
        expect(data['message']).to include('최고 레벨')
        expect(data['errors']).to include('max_level_reached')
      end
    end

    context 'when in cooldown period' do
      before do
        profile.update!(last_level_test_at: 3.days.ago)
        # Create enough workout sessions to pass the workout count check
        20.times do
          session = create(:workout_session, user: user, start_time: 2.weeks.ago, end_time: 2.weeks.ago + 1.hour)
        end
      end

      let(:variables) do
        {
          input: {
            input: {
              exercises: [
                { exerciseType: 'bench', weightKg: 70.0, poseScore: 85.0, formIssues: [] }
              ]
            }
          }
        }
      end

      it 'returns error' do
        result = execute_graphql(query: mutation, variables: variables, context: { current_user: user })

        data = result['data']['submitLevelTestVerification']
        expect(data['success']).to be false
        expect(data['message']).to include('7일')
        expect(data['errors']).to include('not_eligible')
      end
    end

    context 'without profile' do
      let(:user_without_profile) { create(:user) }

      let(:variables) do
        {
          input: {
            input: {
              exercises: [
                { exerciseType: 'bench', weightKg: 70.0, poseScore: 85.0, formIssues: [] }
              ]
            }
          }
        }
      end

      it 'returns error' do
        result = execute_graphql(query: mutation, variables: variables, context: { current_user: user_without_profile })

        data = result['data']['submitLevelTestVerification']
        expect(data['success']).to be false
        expect(data['message']).to include('프로필')
        expect(data['errors']).to include('profile_required')
      end
    end
  end

  describe 'when not authenticated' do
    let(:variables) do
      {
        input: {
          input: {
            exercises: [
              { exerciseType: 'bench', weightKg: 70.0, poseScore: 85.0, formIssues: [] }
            ]
          }
        }
      }
    end

    it 'returns authentication error' do
      result = execute_graphql(query: mutation, variables: variables, context: { current_user: nil })

      data = result['data']['submitLevelTestVerification']
      expect(data['success']).to be false
      expect(data['message']).to include('인증')
      expect(data['errors']).to include('unauthorized')
    end
  end
end
