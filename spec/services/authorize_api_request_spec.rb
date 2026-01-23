# frozen_string_literal: true

require 'rails_helper'

RSpec.describe AuthorizeApiRequest do
  let(:user) { create(:user) }
  let(:valid_token) { JsonWebToken.encode(user_id: user.id) }
  let(:expired_token) { JsonWebToken.encode({ user_id: user.id }, 1.hour.ago) }

  describe '#call' do
    context 'with valid token' do
      let(:headers) { { 'Authorization' => "Bearer #{valid_token}" } }

      it 'returns the user' do
        result = described_class.new(headers).call
        expect(result[:user]).to eq(user)
      end
    end

    context 'with missing token' do
      let(:headers) { {} }

      it 'raises MissingToken error' do
        expect { described_class.new(headers).call }
          .to raise_error(ExceptionHandler::MissingToken, Message.missing_token)
      end
    end

    context 'with invalid token' do
      let(:headers) { { 'Authorization' => 'Bearer invalid_token' } }

      it 'raises DecodeError' do
        expect { described_class.new(headers).call }
          .to raise_error(ExceptionHandler::DecodeError)
      end
    end

    context 'with token for non-existent user' do
      let(:fake_token) { JsonWebToken.encode(user_id: 999999) }
      let(:headers) { { 'Authorization' => "Bearer #{fake_token}" } }

      it 'raises InvalidToken error' do
        expect { described_class.new(headers).call }
          .to raise_error(ExceptionHandler::InvalidToken)
      end
    end

    context 'with expired token' do
      let(:headers) { { 'Authorization' => "Bearer #{expired_token}" } }

      it 'raises ExpiredSignature error' do
        expect { described_class.new(headers).call }
          .to raise_error(ExceptionHandler::ExpiredSignature)
      end
    end
  end
end

RSpec.describe Message do
  describe '.not_found' do
    it 'returns not found message with default record' do
      expect(Message.not_found).to eq('Sorry, record not found.')
    end

    it 'returns not found message with custom record' do
      expect(Message.not_found('user')).to eq('Sorry, user not found.')
    end
  end

  describe '.invalid_credentials' do
    it 'returns invalid credentials message' do
      expect(Message.invalid_credentials).to eq('Invalid credentials')
    end
  end

  describe '.invalid_token' do
    it 'returns invalid token message' do
      expect(Message.invalid_token).to eq('Invalid token')
    end
  end

  describe '.missing_token' do
    it 'returns missing token message' do
      expect(Message.missing_token).to eq('Missing token')
    end
  end

  describe '.unauthorized' do
    it 'returns unauthorized message' do
      expect(Message.unauthorized).to eq('Unauthorized request')
    end
  end

  describe '.account_created' do
    it 'returns account created message' do
      expect(Message.account_created).to eq('Account created successfully')
    end
  end

  describe '.account_not_created' do
    it 'returns account not created message' do
      expect(Message.account_not_created).to eq('Account could not be created')
    end
  end

  describe '.expired_token' do
    it 'returns expired token message' do
      expect(Message.expired_token).to eq('Sorry, your token has expired. Please login to continue.')
    end
  end
end
