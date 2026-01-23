# frozen_string_literal: true

require "rails_helper"

RSpec.describe AiTrainer::LlmGateway do
  describe ".chat" do
    context "without API key (mock mode)" do
      before do
        allow(ENV).to receive(:[]).with("ANTHROPIC_API_KEY").and_return(nil)
      end

      it "returns mock response for general_chat" do
        result = described_class.chat(prompt: "안녕하세요", task: :general_chat)

        expect(result[:success]).to be true
        expect(result[:model]).to eq("mock")
        expect(result[:content]).to be_present
      end

      it "returns mock JSON for routine_generation" do
        result = described_class.chat(prompt: "루틴 만들어줘", task: :routine_generation)

        expect(result[:success]).to be true
        data = JSON.parse(result[:content])
        expect(data["exercises"]).to be_an(Array)
      end

      it "returns mock JSON for condition_check" do
        result = described_class.chat(prompt: "컨디션 체크", task: :condition_check)

        expect(result[:success]).to be true
        data = JSON.parse(result[:content])
        expect(data["score"]).to be_present
      end

      it "returns mock JSON for feedback_analysis" do
        result = described_class.chat(prompt: "피드백", task: :feedback_analysis)

        expect(result[:success]).to be true
        data = JSON.parse(result[:content])
        expect(data["analysis"]).to be_present
      end

      it "returns mock response for level_assessment" do
        result = described_class.chat(prompt: "운동 경험", task: :level_assessment)

        expect(result[:success]).to be true
        expect(result[:content]).to be_present
      end
    end

    context "with API key configured" do
      let(:mock_response) do
        {
          "content" => [{ "text" => "테스트 응답" }],
          "usage" => { "input_tokens" => 10, "output_tokens" => 20 }
        }
      end

      before do
        allow(ENV).to receive(:[]).with("ANTHROPIC_API_KEY").and_return("test-key")
        allow_any_instance_of(Net::HTTP).to receive(:request).and_return(
          double(code: "200", body: mock_response.to_json)
        )
      end

      it "calls Anthropic API and returns response" do
        result = described_class.chat(prompt: "테스트", task: :general_chat)

        expect(result[:success]).to be true
        expect(result[:content]).to eq("테스트 응답")
        expect(result[:usage][:input_tokens]).to eq(10)
      end

      it "uses correct model for routine_generation" do
        request_body = nil
        allow_any_instance_of(Net::HTTP).to receive(:request) do |_, req|
          request_body = JSON.parse(req.body)
          double(code: "200", body: mock_response.to_json)
        end

        described_class.chat(prompt: "루틴", task: :routine_generation)

        expect(request_body["model"]).to eq("claude-sonnet-4-20250514")
      end

      it "uses correct model for general_chat" do
        request_body = nil
        allow_any_instance_of(Net::HTTP).to receive(:request) do |_, req|
          request_body = JSON.parse(req.body)
          double(code: "200", body: mock_response.to_json)
        end

        described_class.chat(prompt: "안녕", task: :general_chat)

        expect(request_body["model"]).to eq("claude-3-5-haiku-20241022")
      end
    end

    context "when API returns error" do
      before do
        allow(ENV).to receive(:[]).with("ANTHROPIC_API_KEY").and_return("test-key")
        allow_any_instance_of(Net::HTTP).to receive(:request).and_return(
          double(code: "500", body: '{"error": "Internal error"}')
        )
      end

      it "returns error response" do
        result = described_class.chat(prompt: "테스트", task: :general_chat)

        expect(result[:success]).to be false
        expect(result[:error]).to include("500")
      end
    end
  end

  describe ".model_for" do
    it "returns routine_generation config" do
      config = described_class.model_for(:routine_generation)
      expect(config[:model]).to eq("claude-sonnet-4-20250514")
    end

    it "returns general_chat config for unknown task" do
      config = described_class.model_for(:unknown_task)
      expect(config[:model]).to eq("claude-3-5-haiku-20241022")
    end
  end

  describe ".configured?" do
    context "with API key" do
      before { allow(ENV).to receive(:[]).with("ANTHROPIC_API_KEY").and_return("key") }

      it "returns true" do
        expect(described_class.configured?).to be true
      end
    end

    context "without API key" do
      before { allow(ENV).to receive(:[]).with("ANTHROPIC_API_KEY").and_return(nil) }

      it "returns false" do
        expect(described_class.configured?).to be false
      end
    end
  end
end
