# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ChatService do
  let(:user) { create(:user, :with_profile) }

  # Helper to mock Claude intent classification
  def mock_intent_classification(intent)
    allow(AiTrainer::LlmGateway).to receive(:chat)
      .with(hash_including(task: :intent_classification))
      .and_return({ success: true, content: intent.to_s })
  end

  describe '.process' do
    subject { described_class.process(user: user, message: message) }

    context 'intent classification with Claude' do
      context 'when message is record pattern (regex-based)' do
        let(:message) { '벤치프레스 60kg 8회' }

        it 'classifies as record_exercise without calling Claude' do
          # Record patterns are still regex-based for accuracy
          allow(ChatRecordService).to receive(:record_exercise).and_return({
                                                                             success: true,
                                                                             session: double,
                                                                             sets: []
                                                                           })

          expect(AiTrainer::LlmGateway).not_to receive(:chat)
            .with(hash_including(task: :intent_classification))

          result = subject
          expect(result[:intent]).to eq('RECORD_EXERCISE')
        end
      end

      context 'when message is query pattern' do
        let(:message) { '벤치프레스 기록 조회해줘' }

        it 'classifies as query_records via Claude' do
          mock_intent_classification(:query_records)
          allow(ChatQueryService).to receive(:query_records).and_return({
                                                                          success: true,
                                                                          records: [],
                                                                          summary: {},
                                                                          interpretation: '조회 결과'
                                                                        })

          result = subject
          expect(result[:intent]).to eq('QUERY_RECORDS')
        end
      end

      context 'when message is condition check' do
        let(:message) { '오늘 컨디션 좋아요' }

        it 'classifies as check_condition via Claude' do
          mock_intent_classification(:check_condition)
          allow(AiTrainer::ConditionService).to receive(:analyze_from_text).and_return({
                                                                                         success: true,
                                                                                         message: '확인했어요',
                                                                                         score: 80
                                                                                       })

          result = subject
          expect(result[:intent]).to eq('CHECK_CONDITION')
        end
      end

      context 'when message is Korean slang for good condition' do
        let(:message) { '구우웃' }

        it 'classifies as check_condition via Claude' do
          mock_intent_classification(:check_condition)
          allow(AiTrainer::ConditionService).to receive(:analyze_from_text).and_return({
                                                                                         success: true,
                                                                                         message: '컨디션 좋으시네요!',
                                                                                         score: 90
                                                                                       })

          result = subject
          expect(result[:intent]).to eq('CHECK_CONDITION')
        end
      end

      context 'when message is routine generation' do
        let(:message) { '오늘의 루틴 만들어줘' }

        it 'classifies as generate_routine via Claude' do
          mock_intent_classification(:generate_routine)
          allow(AiTrainer::RoutineService).to receive(:generate).and_return({ routine_id: '123' })

          result = subject
          expect(result[:intent]).to eq('GENERATE_ROUTINE')
        end
      end

      context 'when message is feedback' do
        let(:message) { '오늘 운동 별로였어요' }

        it 'classifies as submit_feedback via Claude' do
          mock_intent_classification(:submit_feedback)
          allow(AiTrainer::FeedbackService).to receive(:analyze_from_text).and_return({
                                                                                        success: true,
                                                                                        message: '피드백 감사해요'
                                                                                      })

          result = subject
          expect(result[:intent]).to eq('SUBMIT_FEEDBACK')
        end
      end

      context 'when message is general chat' do
        let(:message) { '오늘 날씨 어때?' }

        it 'classifies as general_chat via Claude' do
          mock_intent_classification(:general_chat)
          allow(AiTrainer::ChatService).to receive(:general_chat).and_return({
                                                                               success: true,
                                                                               message: '운동 전문 트레이너입니다!'
                                                                             })

          result = subject
          expect(result[:intent]).to eq('GENERAL_CHAT')
        end
      end

      context 'when Claude returns unknown intent' do
        let(:message) { '뭔가 이상한 메시지' }

        it 'defaults to general_chat' do
          allow(AiTrainer::LlmGateway).to receive(:chat)
            .with(hash_including(task: :intent_classification))
            .and_return({ success: true, content: 'unknown_intent_xyz' })
          allow(AiTrainer::ChatService).to receive(:general_chat).and_return({
                                                                               success: true,
                                                                               message: '무엇을 도와드릴까요?'
                                                                             })

          result = subject
          expect(result[:intent]).to eq('GENERAL_CHAT')
        end
      end

      context 'when Claude API fails' do
        let(:message) { '테스트 메시지' }

        it 'defaults to general_chat' do
          allow(AiTrainer::LlmGateway).to receive(:chat)
            .with(hash_including(task: :intent_classification))
            .and_return({ success: false, error: 'API error' })
          allow(AiTrainer::ChatService).to receive(:general_chat).and_return({
                                                                               success: true,
                                                                               message: '무엇을 도와드릴까요?'
                                                                             })

          result = subject
          expect(result[:intent]).to eq('GENERAL_CHAT')
        end
      end
    end

    context 'record patterns' do
      before do
        allow(ChatRecordService).to receive(:record_exercise).and_return({
                                                                           success: true,
                                                                           session: double,
                                                                           sets: []
                                                                         })
      end

      it 'parses "벤치프레스 60kg 8회"' do
        result = described_class.process(user: user, message: '벤치프레스 60kg 8회')
        expect(result[:success]).to be true
        expect(result[:intent]).to eq('RECORD_EXERCISE')
      end

      it 'parses "스쿼트 80킬로 10회 4세트"' do
        result = described_class.process(user: user, message: '스쿼트 80킬로 10회 4세트')
        expect(result[:success]).to be true
      end

      it 'parses "풀업 8회"' do
        result = described_class.process(user: user, message: '풀업 8회')
        expect(result[:success]).to be true
      end

      it 'parses "데드리프트 4세트 8회"' do
        result = described_class.process(user: user, message: '데드리프트 4세트 8회')
        expect(result[:success]).to be true
      end
    end

    context 'error handling' do
      let(:message) { '벤치프레스 60kg 8회' }

      it 'handles service errors gracefully' do
        allow(ChatRecordService).to receive(:record_exercise).and_raise(StandardError, 'Test error')

        result = subject
        expect(result[:success]).to be false
        expect(result[:error]).to include('오류')
      end
    end
  end

  describe 'parse_exercise_record' do
    let(:service) { described_class.new(user: user, message: message) }

    context 'with weight and reps' do
      let(:message) { '벤치프레스 60kg 8회' }

      it 'parses correctly' do
        result = service.send(:parse_exercise_record)
        expect(result[:exercise]).to eq('벤치프레스')
        expect(result[:weight]).to eq(60.0)
        expect(result[:reps]).to eq(8)
      end
    end

    context 'with sets (no weight)' do
      # Pattern with weight matches before sets pattern, so use "세트 회" format
      let(:message) { '데드리프트 4세트 8회' }

      it 'parses sets correctly' do
        result = service.send(:parse_exercise_record)
        expect(result[:exercise]).to eq('데드리프트')
        expect(result[:sets]).to eq(4)
        expect(result[:reps]).to eq(8)
      end
    end

    context 'bodyweight exercise' do
      let(:message) { '풀업 8회' }

      it 'parses without weight' do
        result = service.send(:parse_exercise_record)
        expect(result[:exercise]).to eq('풀업')
        expect(result[:weight]).to be_nil
        expect(result[:reps]).to eq(8)
      end
    end
  end

  describe 'parse_query_params' do
    let(:service) { described_class.new(user: user, message: message) }

    context 'with time range' do
      let(:message) { '이번주 벤치프레스 기록' }

      it 'parses time range' do
        result = service.send(:parse_query_params)
        expect(result[:time_range]).to eq(:this_week)
        expect(result[:exercise_name]).to eq('벤치프레스')
      end
    end

    context 'with aggregation' do
      let(:message) { '벤치프레스 최고 기록' }

      it 'parses aggregation' do
        result = service.send(:parse_query_params)
        expect(result[:aggregation]).to eq(:max)
      end
    end
  end
end
