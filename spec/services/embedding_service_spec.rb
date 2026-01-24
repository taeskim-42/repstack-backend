# frozen_string_literal: true

require "rails_helper"

RSpec.describe EmbeddingService do
  describe ".configured?" do
    it "returns true when Gemini API key is present" do
      allow(GeminiConfig).to receive(:configured?).and_return(true)
      expect(described_class.configured?).to be true
    end

    it "returns false when Gemini API key is missing" do
      allow(GeminiConfig).to receive(:configured?).and_return(false)
      expect(described_class.configured?).to be false
    end
  end

  describe ".generate" do
    context "when not configured" do
      before do
        allow(described_class).to receive(:configured?).and_return(false)
      end

      it "raises an error" do
        expect { described_class.generate("test") }.to raise_error("Gemini API key not configured")
      end
    end

    context "when configured" do
      let(:mock_embedding) { Array.new(768) { rand } }
      let(:mock_response) do
        {
          "embedding" => {
            "values" => mock_embedding
          }
        }
      end

      before do
        allow(described_class).to receive(:configured?).and_return(true)
        allow(GeminiConfig).to receive(:api_key).and_return("test-key")

        stub_request(:post, /generativelanguage\.googleapis\.com.*embedContent/)
          .to_return(status: 200, body: mock_response.to_json, headers: { "Content-Type" => "application/json" })
      end

      it "returns embedding vector" do
        result = described_class.generate("test text")

        expect(result).to be_an(Array)
        expect(result.length).to eq(768)
      end

      it "returns nil for blank text" do
        expect(described_class.generate("")).to be_nil
        expect(described_class.generate(nil)).to be_nil
      end
    end
  end

  describe ".embed_knowledge_chunk" do
    let(:chunk) { create(:fitness_knowledge_chunk) }

    context "when pgvector is not available" do
      before do
        allow(described_class).to receive(:pgvector_available?).and_return(false)
      end

      it "returns early without generating embedding" do
        expect(described_class).not_to receive(:generate)
        described_class.embed_knowledge_chunk(chunk)
      end
    end

    context "when pgvector is available" do
      let(:mock_embedding) { Array.new(1536) { rand } }

      before do
        allow(described_class).to receive(:pgvector_available?).and_return(true)
        allow(described_class).to receive(:generate).and_return(mock_embedding)
        allow(chunk).to receive(:update!)
      end

      it "generates and saves embedding" do
        described_class.embed_knowledge_chunk(chunk)

        expect(described_class).to have_received(:generate)
        expect(chunk).to have_received(:update!).with(embedding: mock_embedding)
      end
    end
  end

  describe ".generate_query_embedding" do
    before do
      allow(described_class).to receive(:generate).and_return([1, 2, 3])
    end

    it "calls generate with the query" do
      described_class.generate_query_embedding("how to do bench press")

      expect(described_class).to have_received(:generate).with("how to do bench press")
    end
  end
end
