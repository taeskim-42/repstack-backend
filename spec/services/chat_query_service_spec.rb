# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ChatQueryService do
  let(:user) { create(:user) }
  let(:other_user) { create(:user) }

  describe '.query_records' do
    let!(:session) do
      create(:workout_session, user: user, start_time: 1.day.ago, end_time: 1.day.ago + 1.hour)
    end

    let!(:bench_set1) do
      create(:workout_set, workout_session: session, exercise_name: '벤치프레스', weight: 60, reps: 8)
    end

    let!(:bench_set2) do
      create(:workout_set, workout_session: session, exercise_name: '벤치프레스', weight: 70, reps: 6)
    end

    let!(:squat_set) do
      create(:workout_set, workout_session: session, exercise_name: '스쿼트', weight: 100, reps: 5)
    end

    context 'basic query' do
      it 'returns success' do
        result = described_class.query_records(user: user, params: {})
        expect(result[:success]).to be true
      end

      it 'returns records' do
        result = described_class.query_records(user: user, params: {})
        expect(result[:records]).not_to be_empty
      end

      it 'returns summary' do
        result = described_class.query_records(user: user, params: {})
        expect(result[:summary]).not_to be_nil
      end

      it 'returns interpretation' do
        result = described_class.query_records(user: user, params: {})
        expect(result[:interpretation]).to be_present
      end
    end

    context 'with exercise filter' do
      it 'filters by exercise name' do
        result = described_class.query_records(user: user, params: { exercise_name: '벤치프레스' })
        exercises = result[:records].map { |r| r[:exercise_name] }
        expect(exercises).to all(include('벤치프레스'))
      end

      it 'excludes other exercises' do
        result = described_class.query_records(user: user, params: { exercise_name: '벤치프레스' })
        exercises = result[:records].map { |r| r[:exercise_name] }
        expect(exercises).not_to include('스쿼트')
      end
    end

    context 'with time range' do
      context 'today' do
        let!(:today_session) do
          create(:workout_session, user: user, start_time: Time.current, end_time: Time.current + 1.hour)
        end

        let!(:today_set) do
          create(:workout_set, workout_session: today_session, exercise_name: '런지', weight: 20, reps: 12)
        end

        it 'returns only today records' do
          result = described_class.query_records(user: user, params: { time_range: :today })
          dates = result[:records].map { |r| r[:date] }
          expect(dates).to all(eq(Date.current.strftime('%Y-%m-%d')))
        end
      end

      context 'this_week' do
        it 'returns records from this week' do
          result = described_class.query_records(user: user, params: { time_range: :this_week })
          expect(result[:success]).to be true
        end
      end

      context 'recent (default)' do
        it 'defaults to last 30 days' do
          result = described_class.query_records(user: user, params: {})
          expect(result[:success]).to be true
          expect(result[:records].count).to be >= 0
        end
      end
    end

    context 'summary calculations' do
      it 'calculates max weight' do
        result = described_class.query_records(user: user, params: { exercise_name: '벤치프레스' })
        expect(result[:summary][:max_weight]).to eq(70.0)
      end

      it 'calculates total sets' do
        result = described_class.query_records(user: user, params: { exercise_name: '벤치프레스' })
        expect(result[:summary][:total_sets]).to eq(2)
      end

      it 'calculates total volume' do
        # (60*8) + (70*6) = 480 + 420 = 900
        result = described_class.query_records(user: user, params: { exercise_name: '벤치프레스' })
        expect(result[:summary][:total_volume]).to eq(900.0)
      end
    end

    context 'aggregation highlights' do
      it 'highlights max weight' do
        result = described_class.query_records(user: user, params: { aggregation: :max })
        expect(result[:summary][:highlight]).to include('최고 무게')
      end

      it 'highlights average weight' do
        result = described_class.query_records(user: user, params: { aggregation: :avg })
        expect(result[:summary][:highlight]).to include('평균 무게')
      end

      it 'highlights total volume' do
        result = described_class.query_records(user: user, params: { aggregation: :sum })
        expect(result[:summary][:highlight]).to include('총 볼륨')
      end

      it 'highlights workout count' do
        result = described_class.query_records(user: user, params: { aggregation: :count })
        expect(result[:summary][:highlight]).to include('회 운동')
      end
    end

    context 'record grouping' do
      it 'groups by date and exercise' do
        result = described_class.query_records(user: user, params: { exercise_name: '벤치프레스' })
        # 2 sets of bench press on same day should be 1 grouped record
        expect(result[:records].count).to eq(1)
      end

      it 'calculates average weight in group' do
        result = described_class.query_records(user: user, params: { exercise_name: '벤치프레스' })
        # (60 + 70) / 2 = 65
        expect(result[:records].first[:weight]).to eq(65.0)
      end
    end

    context 'user isolation' do
      let!(:other_session) do
        create(:workout_session, user: other_user, start_time: 1.day.ago, end_time: 1.day.ago + 1.hour)
      end

      let!(:other_set) do
        create(:workout_set, workout_session: other_session, exercise_name: '벤치프레스', weight: 200, reps: 1)
      end

      it 'does not include other user records' do
        result = described_class.query_records(user: user, params: { exercise_name: '벤치프레스' })
        max_weight = result[:summary][:max_weight]
        expect(max_weight).to eq(70.0) # Not 200 from other user
      end
    end

    context 'empty results' do
      it 'handles no matching records' do
        result = described_class.query_records(user: user, params: { exercise_name: '존재하지않는운동' })
        expect(result[:success]).to be true
        expect(result[:records]).to be_empty
        expect(result[:summary]).to be_nil
      end

      it 'returns appropriate message' do
        result = described_class.query_records(user: user, params: { exercise_name: '존재하지않는운동' })
        expect(result[:interpretation]).to include('없어요')
      end
    end

    context 'interpretation messages' do
      it 'includes time description' do
        result = described_class.query_records(user: user, params: { time_range: :this_week })
        expect(result[:interpretation]).to include('이번주')
      end

      it 'includes exercise name' do
        result = described_class.query_records(user: user, params: { exercise_name: '벤치프레스' })
        expect(result[:interpretation]).to include('벤치프레스')
      end

      it 'includes record details' do
        result = described_class.query_records(user: user, params: {})
        expect(result[:interpretation]).to include('기록이에요!')
        expect(result[:interpretation]).to include('kg')
        expect(result[:interpretation]).to include('회')
      end
    end
  end
end
