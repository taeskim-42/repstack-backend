# frozen_string_literal: true

require "rails_helper"

RSpec.describe AgentBridge do
  let(:user) { create(:user, :with_profile) }

  describe ".routine_text_detected?" do
    it "detects Korean routine text with sets and reps" do
      text = "오늘의 루틴입니다:\n\n1. 벤치프레스 3세트 10회\n2. 스쿼트 4세트 8회\n3. 데드리프트 3세트 5회"
      expect(described_class.send(:routine_text_detected?, text)).to be true
    end

    it "detects English routine text with sets and reps" do
      text = "Here's your routine:\n\n1. Bench Press 3 set 10 rep\n2. Squat 4 set 8 rep\n3. Deadlift 3 set 5 rep"
      expect(described_class.send(:routine_text_detected?, text)).to be true
    end

    it "rejects normal chat without routine patterns" do
      text = "안녕하세요! 오늘 운동 어떻게 할까요?"
      expect(described_class.send(:routine_text_detected?, text)).to be false
    end

    it "rejects blank text" do
      expect(described_class.send(:routine_text_detected?, "")).to be false
      expect(described_class.send(:routine_text_detected?, nil)).to be false
    end

    it "rejects text with keywords but not enough newlines" do
      text = "벤치프레스 3세트 10회 하세요"
      expect(described_class.send(:routine_text_detected?, text)).to be false
    end
  end

  describe ".find_today_routine_for_user" do
    it "returns today's incomplete routine" do
      routine = create(:workout_routine, :with_exercises, user: user, created_at: Time.current)

      result = described_class.send(:find_today_routine_for_user, user)
      expect(result).to be_present
      expect(result[:routine_id]).to eq(routine.id.to_s)
      expect(result[:exercises]).to be_an(Array)
    end

    it "ignores completed routines" do
      create(:workout_routine, :completed, user: user, created_at: Time.current)

      result = described_class.send(:find_today_routine_for_user, user)
      expect(result).to be_nil
    end

    it "ignores yesterday's routines" do
      create(:workout_routine, user: user, created_at: 1.day.ago)

      result = described_class.send(:find_today_routine_for_user, user)
      expect(result).to be_nil
    end

    it "returns nil for nil user" do
      expect(described_class.send(:find_today_routine_for_user, nil)).to be_nil
    end
  end

  describe ".parse_response — routine fallback" do
    let(:http_response) { instance_double(Net::HTTPOK, is_a?: true) }

    before do
      allow(http_response).to receive(:is_a?).with(Net::HTTPSuccess).and_return(true)
    end

    context "when agent returns routine text without tool calls" do
      let!(:routine) { create(:workout_routine, :with_exercises, user: user, created_at: Time.current) }

      it "overrides intent to GENERATE_ROUTINE" do
        allow(http_response).to receive(:body).and_return({
          success: true,
          message: "오늘의 루틴입니다:\n\n1. 벤치프레스 3세트 10회\n2. 스쿼트 4세트 8회\n3. 데드리프트 3세트 5회",
          tool_calls: [],
          usage: { input_tokens: 100, output_tokens: 50 }
        }.to_json)

        result = described_class.send(:parse_response, http_response, user)

        expect(result[:intent]).to eq("GENERATE_ROUTINE")
        expect(result[:data][:routine]).to be_present
        expect(result[:data][:routine][:routine_id]).to eq(routine.id.to_s)
      end
    end

    context "when agent returns normal chat" do
      it "keeps GENERAL_CHAT intent" do
        allow(http_response).to receive(:body).and_return({
          success: true,
          message: "안녕하세요! 오늘 운동 준비되셨나요?",
          tool_calls: [],
          usage: { input_tokens: 100, output_tokens: 50 }
        }.to_json)

        result = described_class.send(:parse_response, http_response, user)

        expect(result[:intent]).to eq("GENERAL_CHAT")
      end
    end

    context "when agent properly used generate_routine tool" do
      it "uses tool-based intent (no fallback)" do
        allow(http_response).to receive(:body).and_return({
          success: true,
          message: "루틴을 생성했습니다!",
          tool_calls: [ { name: "generate_routine", input: {}, result: { routine: { id: 1 } } } ],
          usage: { input_tokens: 100, output_tokens: 50 }
        }.to_json)

        result = described_class.send(:parse_response, http_response, user)

        expect(result[:intent]).to eq("GENERATE_ROUTINE")
      end
    end

    context "when routine text detected but no today routine exists" do
      it "keeps GENERAL_CHAT intent" do
        allow(http_response).to receive(:body).and_return({
          success: true,
          message: "오늘의 루틴입니다:\n\n1. 벤치프레스 3세트 10회\n2. 스쿼트 4세트 8회\n3. 데드리프트 3세트 5회",
          tool_calls: [],
          usage: { input_tokens: 100, output_tokens: 50 }
        }.to_json)

        result = described_class.send(:parse_response, http_response, user)

        expect(result[:intent]).to eq("GENERAL_CHAT")
      end
    end
  end
end
