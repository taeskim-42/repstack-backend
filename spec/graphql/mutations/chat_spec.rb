# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Mutations::Chat, type: :graphql do
  let(:user) { create(:user, :with_profile) }

  let(:mutation) do
    <<~GQL
      mutation Chat($message: String!, $routineId: ID, $sessionId: String) {
        chat(input: { message: $message, routineId: $routineId, sessionId: $sessionId }) {
          success
          message
          intent
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
    context 'with record exercise intent' do
      it 'records exercise with weight and reps' do
        result = execute_mutation({ message: '벤치프레스 60kg 8회' })

        data = result['data']['chat']
        expect(data['success']).to be true
        expect(data['intent']).to eq('RECORD_EXERCISE')
        expect(data['message']).to include('기록했어요')
      end

      it 'records exercise with sets' do
        result = execute_mutation({ message: '스쿼트 80킬로 10회 4세트' })

        data = result['data']['chat']
        expect(data['success']).to be true
        expect(data['intent']).to eq('RECORD_EXERCISE')
        expect(data['message']).to include('기록했어요')
      end

      it 'records bodyweight exercise' do
        result = execute_mutation({ message: '풀업 8회' })

        data = result['data']['chat']
        expect(data['success']).to be true
        expect(data['intent']).to eq('RECORD_EXERCISE')
      end

      it 'creates workout sets in database' do
        expect do
          execute_mutation({ message: '데드리프트 100kg 5회' })
        end.to change { WorkoutSet.count }.by(1)
      end
    end

    context 'with query records intent' do
      let!(:session) do
        create(:workout_session, user: user, start_time: 1.day.ago, end_time: 1.day.ago + 1.hour)
      end

      let!(:bench_set) do
        create(:workout_set, workout_session: session, exercise_name: '벤치프레스', weight: 60, reps: 8)
      end

      it 'queries records by exercise name' do
        result = execute_mutation({ message: '벤치프레스 기록 조회해줘' })

        data = result['data']['chat']
        expect(data['success']).to be true
        expect(data['intent']).to eq('QUERY_RECORDS')
      end

      it 'handles max weight query' do
        result = execute_mutation({ message: '벤치프레스 최고 기록' })

        data = result['data']['chat']
        expect(data['success']).to be true
      end
    end

    context 'with off-topic message' do
      it 'responds with fitness prompt' do
        result = execute_mutation({ message: '오늘 날씨 어때?' })

        data = result['data']['chat']
        expect(data['success']).to be true
        expect(data['intent']).to eq('OFF_TOPIC')
        expect(data['message']).to include('운동')
      end
    end

    context 'with check condition intent' do
      before do
        # Mock the AI service to avoid actual API calls
        allow(AiTrainer::ConditionService).to receive(:analyze_from_text).and_return({
                                                                                       success: true,
                                                                                       message: '컨디션을 확인했어요!',
                                                                                       score: 80,
                                                                                       status: 'good',
                                                                                       adaptations: [],
                                                                                       recommendations: []
                                                                                     })
      end

      it 'analyzes condition from text' do
        result = execute_mutation({ message: '오늘 컨디션 좋아요!' })

        data = result['data']['chat']
        expect(data['success']).to be true
        expect(data['intent']).to eq('CHECK_CONDITION')
      end
    end

    context 'with generate routine intent' do
      before do
        user.user_profile.update!(current_level: 'intermediate')

        # Mock the AI service to avoid actual API calls
        allow(AiTrainer::RoutineService).to receive(:generate).and_return({
                                                                            routine_id: 'test-routine-123',
                                                                            exercises: []
                                                                          })
      end

      it 'generates routine' do
        result = execute_mutation({ message: '오늘의 루틴 만들어줘' })

        data = result['data']['chat']
        expect(data['success']).to be true
        expect(data['intent']).to eq('GENERATE_ROUTINE')
      end
    end

    context 'with empty message' do
      it 'handles empty message gracefully' do
        result = execute_mutation({ message: '' })

        data = result['data']['chat']
        # Should be off-topic or error
        expect(data['success']).to be true
        expect(data['intent']).to eq('OFF_TOPIC')
      end
    end

    context 'with special characters' do
      it 'handles special characters safely' do
        result = execute_mutation({ message: "벤치프레스 60kg 8회 <script>alert('xss')</script>" })

        data = result['data']['chat']
        # Should still work without executing script
        expect(data['success']).to be true
      end
    end

    context 'with very long message' do
      it 'handles long message without crashing' do
        long_message = '벤치프레스 60kg 8회 ' * 50
        result = execute_mutation({ message: long_message })

        data = result['data']['chat']
        # Should not crash, either success or graceful error
        expect(data).not_to be_nil
      end
    end
  end

  describe 'when not authenticated' do
    it 'returns authentication error' do
      result = execute_mutation({ message: '벤치프레스 60kg 8회' }, current_user: nil)

      expect(result['errors']).to be_present
      expect(result['errors'].first['message']).to include('Authentication required')
    end
  end
end
