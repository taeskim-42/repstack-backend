# frozen_string_literal: true

require "rails_helper"

RSpec.describe HealthController, type: :request do
  describe "GET /health" do
    it "returns ok status" do
      get "/health"

      expect(response).to have_http_status(:ok)
      json = JSON.parse(response.body)
      expect(json["status"]).to eq("ok")
      expect(json["service"]).to eq("repstack-backend")
    end
  end

  describe "GET /health/ready" do
    context "when all services are healthy" do
      it "returns ready status" do
        get "/health/ready"

        expect(response).to have_http_status(:ok)
        json = JSON.parse(response.body)
        expect(json["status"]).to eq("ready")
        expect(json["checks"]["database"]["healthy"]).to be true
        expect(json["checks"]["cache"]["healthy"]).to be true
      end
    end

    context "when database is unhealthy" do
      before do
        allow(ActiveRecord::Base.connection).to receive(:execute).and_raise(ActiveRecord::ConnectionNotEstablished)
      end

      it "returns service unavailable" do
        get "/health/ready"

        expect(response).to have_http_status(:service_unavailable)
        json = JSON.parse(response.body)
        expect(json["status"]).to eq("not_ready")
      end
    end
  end

  describe "GET /health/live" do
    it "returns alive status" do
      get "/health/live"

      expect(response).to have_http_status(:ok)
      json = JSON.parse(response.body)
      expect(json["status"]).to eq("alive")
    end
  end

  describe "GET /health/details" do
    before do
      # Allow ENV.fetch to work normally but provide a default for APP_VERSION
      allow(ENV).to receive(:fetch).and_call_original
      allow(ENV).to receive(:fetch).with("APP_VERSION").and_return("test-version")
      # Mock circuit stats for consistent test behavior
      allow(ClaudeApiService).to receive(:circuit_stats).and_return({
        open: false,
        error_rate: 0.0,
        success_count: 0,
        failure_count: 0
      })
    end

    it "returns detailed health information" do
      get "/health/details"

      expect(response).to have_http_status(:ok)
      json = JSON.parse(response.body)

      expect(json["status"]).to eq("healthy")
      expect(json["service"]).to eq("repstack-backend")
      expect(json["environment"]).to eq("test")
      expect(json["ruby_version"]).to be_present
      expect(json["rails_version"]).to be_present

      # Check all health checks are present
      expect(json["checks"]).to include("database", "cache", "claude_api", "memory")
    end

    context "when Claude API circuit is open" do
      before do
        allow(ENV).to receive(:fetch).and_call_original
        allow(ENV).to receive(:fetch).with("APP_VERSION").and_return("test-version")
        allow(ClaudeApiService).to receive(:circuit_stats).and_return({
          open: true,
          error_rate: 0.5
        })
      end

      it "reports circuit breaker status" do
        get "/health/details"

        json = JSON.parse(response.body)
        expect(json["checks"]["claude_api"]["circuit_open"]).to be true
      end
    end

    context "when memory usage is high" do
      before do
        allow(ENV).to receive(:fetch).and_call_original
        allow(ENV).to receive(:fetch).with("APP_VERSION").and_return("test-version")
        allow(ClaudeApiService).to receive(:circuit_stats).and_return({
          open: false,
          error_rate: 0.0,
          success_count: 0,
          failure_count: 0
        })
        # Mock ps command output (in KB) - 600MB = 614400KB
        allow_any_instance_of(HealthController).to receive(:`).with(/ps -o rss=/).and_return("614400")
      end

      it "reports unhealthy memory status" do
        get "/health/details"

        json = JSON.parse(response.body)
        expect(json["checks"]["memory"]["healthy"]).to be false
      end
    end
  end
end
