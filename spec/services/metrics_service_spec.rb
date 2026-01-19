# frozen_string_literal: true

require "rails_helper"

RSpec.describe MetricsService do
  describe ".record_signup" do
    context "when metrics are enabled" do
      before do
        allow(described_class).to receive(:metrics_enabled?).and_return(true)
      end

      it "records successful signup" do
        expect(Yabeda.repstack.signups_total).to receive(:increment).with({ status: "success" })
        described_class.record_signup(success: true)
      end

      it "records failed signup" do
        expect(Yabeda.repstack.signups_total).to receive(:increment).with({ status: "failure" })
        described_class.record_signup(success: false)
      end
    end

    context "when metrics are disabled" do
      before do
        allow(described_class).to receive(:metrics_enabled?).and_return(false)
      end

      it "does nothing" do
        expect(Yabeda.repstack.signups_total).not_to receive(:increment)
        described_class.record_signup(success: true)
      end
    end

    context "when an error occurs" do
      before do
        allow(described_class).to receive(:metrics_enabled?).and_return(true)
        allow(Yabeda.repstack.signups_total).to receive(:increment).and_raise(StandardError, "test error")
      end

      it "logs the error and continues" do
        expect(Rails.logger).to receive(:debug).with(/record_signup failed/)
        described_class.record_signup(success: true)
      end
    end
  end

  describe ".record_login" do
    context "when metrics are enabled" do
      before do
        allow(described_class).to receive(:metrics_enabled?).and_return(true)
      end

      it "records successful login" do
        expect(Yabeda.repstack.logins_total).to receive(:increment).with({ status: "success" })
        described_class.record_login(success: true)
      end
    end
  end

  describe ".record_workout_session_created" do
    context "when metrics are enabled" do
      before do
        allow(described_class).to receive(:metrics_enabled?).and_return(true)
      end

      it "records session creation" do
        expect(Yabeda.repstack.workout_sessions_total).to receive(:increment).with({ status: "success" })
        described_class.record_workout_session_created(success: true)
      end
    end
  end

  describe ".record_workout_set_logged" do
    context "when metrics are enabled" do
      before do
        allow(described_class).to receive(:metrics_enabled?).and_return(true)
      end

      it "records workout set" do
        expect(Yabeda.repstack.workout_sets_total).to receive(:increment).with({})
        described_class.record_workout_set_logged
      end
    end
  end

  describe ".record_workout_session_duration" do
    context "when metrics are enabled" do
      before do
        allow(described_class).to receive(:metrics_enabled?).and_return(true)
      end

      it "records duration" do
        expect(Yabeda.repstack.workout_session_duration_seconds).to receive(:measure).with({}, 120)
        described_class.record_workout_session_duration(120)
      end
    end
  end

  describe ".record_routine_generation" do
    context "when metrics are enabled" do
      before do
        allow(described_class).to receive(:metrics_enabled?).and_return(true)
      end

      it "records routine generation" do
        expect(Yabeda.repstack.routine_generations_total).to receive(:increment).with({
          status: "success",
          level: "beginner",
          mock: "false"
        })
        expect(Yabeda.repstack.routine_generation_duration_seconds).to receive(:measure).with({}, 1.5)
        described_class.record_routine_generation(success: true, level: "beginner", mock: false, duration_seconds: 1.5)
      end
    end
  end

  describe ".record_circuit_state" do
    context "when metrics are enabled" do
      before do
        allow(described_class).to receive(:metrics_enabled?).and_return(true)
      end

      it "records closed state as 0" do
        expect(Yabeda.repstack.circuit_breaker_state).to receive(:set).with({ circuit_name: "claude_api" }, 0)
        described_class.record_circuit_state("claude_api", :closed)
      end

      it "records open state as 1" do
        expect(Yabeda.repstack.circuit_breaker_state).to receive(:set).with({ circuit_name: "claude_api" }, 1)
        described_class.record_circuit_state("claude_api", :open)
      end

      it "records half_open state as 2" do
        expect(Yabeda.repstack.circuit_breaker_state).to receive(:set).with({ circuit_name: "claude_api" }, 2)
        described_class.record_circuit_state("claude_api", :half_open)
      end
    end
  end

  describe ".record_circuit_trip" do
    context "when metrics are enabled" do
      before do
        allow(described_class).to receive(:metrics_enabled?).and_return(true)
      end

      it "records circuit trip" do
        expect(Yabeda.repstack.circuit_breaker_trips_total).to receive(:increment).with({ circuit_name: "test_circuit" })
        described_class.record_circuit_trip("test_circuit")
      end
    end
  end

  describe ".record_rate_limit_hit" do
    context "when metrics are enabled" do
      before do
        allow(described_class).to receive(:metrics_enabled?).and_return(true)
      end

      it "records rate limit hit" do
        expect(Yabeda.repstack.rate_limit_hits_total).to receive(:increment).with({ throttle_name: "req/ip" })
        described_class.record_rate_limit_hit("req/ip")
      end
    end
  end

  describe ".record_db_query" do
    context "when metrics are enabled" do
      before do
        allow(described_class).to receive(:metrics_enabled?).and_return(true)
      end

      it "records database query" do
        expect(Yabeda.database.query_duration_seconds).to receive(:measure).with({ operation: "select" }, 0.05)
        described_class.record_db_query("select", 0.05)
      end
    end
  end

  describe ".update_connection_pool_metrics" do
    context "when metrics are enabled" do
      before do
        allow(described_class).to receive(:metrics_enabled?).and_return(true)
      end

      it "updates pool metrics" do
        expect(Yabeda.database.connection_pool_size).to receive(:set)
        expect(Yabeda.database.connection_pool_active).to receive(:set)
        described_class.update_connection_pool_metrics
      end
    end
  end

  describe ".measure_time" do
    it "returns result and duration" do
      result, duration = described_class.measure_time { "test_result" }
      expect(result).to eq("test_result")
      expect(duration).to be_a(Float)
      expect(duration).to be >= 0
    end
  end
end
