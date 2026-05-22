# frozen_string_literal: true

require 'rails_helper'

RSpec.describe AiTrainer::VoiceJsonParser do
  describe '.extract' do
    it 'unwraps ```json fenced blocks' do
      text = <<~TXT
        Sure, here's the JSON:
        ```json
        {"a": 1, "b": "hi"}
        ```
        Let me know if you need more.
      TXT

      expect(described_class.extract(text)).to eq('{"a": 1, "b": "hi"}')
    end

    it 'unwraps bare ``` fenced blocks' do
      text = "```\n{\"x\": 2}\n```"
      expect(described_class.extract(text)).to eq('{"x": 2}')
    end

    it 'returns the brace-bound substring when not fenced' do
      text = "prose before {\"y\": 3} prose after"
      expect(described_class.extract(text)).to eq('{"y": 3}')
    end

    it 'returns raw JSON unchanged' do
      text = '{"z": 4}'
      expect(described_class.extract(text)).to eq('{"z": 4}')
    end

    it 'handles nil input' do
      expect(described_class.extract(nil)).to be_nil
    end

    it 'falls back to fence-stripped text when no braces are present' do
      expect(described_class.extract("```json\nbroken\n```")).to eq("broken")
    end
  end

  describe '.parse' do
    it 'returns the parsed hash for fenced JSON' do
      expect(described_class.parse("```json\n{\"a\": 1}\n```")).to eq("a" => 1)
    end

    it 'returns nil on malformed JSON' do
      expect(described_class.parse("not json at all")).to be_nil
    end
  end
end
