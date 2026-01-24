# frozen_string_literal: true

require "rails_helper"

RSpec.describe FitnessTestSubmission, type: :model do
  describe "associations" do
    it { is_expected.to belong_to(:user) }
  end

  describe "validations" do
    subject { build(:fitness_test_submission) }

    it { is_expected.to validate_presence_of(:job_id) }
    it { is_expected.to validate_uniqueness_of(:job_id) }
    it { is_expected.to validate_presence_of(:status) }
    it { is_expected.to validate_inclusion_of(:status).in_array(FitnessTestSubmission::STATUSES) }
  end

  describe "scopes" do
    let!(:pending_submission) { create(:fitness_test_submission, status: "pending") }
    let!(:processing_submission) { create(:fitness_test_submission, :processing) }
    let!(:completed_submission) { create(:fitness_test_submission, :completed) }
    let!(:failed_submission) { create(:fitness_test_submission, :failed) }

    it "returns pending submissions" do
      expect(described_class.pending).to contain_exactly(pending_submission)
    end

    it "returns processing submissions" do
      expect(described_class.processing).to contain_exactly(processing_submission)
    end

    it "returns completed submissions" do
      expect(described_class.completed).to contain_exactly(completed_submission)
    end

    it "returns failed submissions" do
      expect(described_class.failed).to contain_exactly(failed_submission)
    end
  end

  describe "#start_processing!" do
    let(:submission) { create(:fitness_test_submission, status: "pending") }

    it "updates status to processing" do
      expect { submission.start_processing! }.to change { submission.status }.from("pending").to("processing")
    end

    it "sets started_at timestamp" do
      submission.start_processing!
      expect(submission.started_at).to be_within(1.second).of(Time.current)
    end
  end

  describe "#complete_with_results!" do
    let(:submission) { create(:fitness_test_submission, :processing) }
    let(:result) do
      {
        fitness_score: 80,
        assigned_level: 4,
        assigned_tier: "intermediate",
        message: "Great job!"
      }
    end

    it "updates status to completed" do
      expect { submission.complete_with_results!(result) }.to change { submission.status }.from("processing").to("completed")
    end

    it "stores evaluation results" do
      submission.complete_with_results!(result)
      expect(submission.fitness_score).to eq(80)
      expect(submission.assigned_level).to eq(4)
      expect(submission.assigned_tier).to eq("intermediate")
    end
  end

  describe "#fail_with_error!" do
    let(:submission) { create(:fitness_test_submission, :processing) }

    it "updates status to failed" do
      expect { submission.fail_with_error!("Test error") }.to change { submission.status }.from("processing").to("failed")
    end

    it "stores error message" do
      submission.fail_with_error!("Test error")
      expect(submission.error_message).to eq("Test error")
    end
  end

  describe "#video_key_for" do
    let(:submission) { create(:fitness_test_submission) }

    it "returns video key for existing exercise type" do
      expect(submission.video_key_for("pushup")).to be_present
      expect(submission.video_key_for("pushup")).to include("pushup")
    end

    it "returns nil for non-existing exercise type" do
      expect(submission.video_key_for("unknown")).to be_nil
    end
  end

  describe "#all_video_keys" do
    let(:submission) { create(:fitness_test_submission) }

    it "returns all video keys" do
      expect(submission.all_video_keys.size).to eq(3)
    end
  end

  describe "#exercise_types" do
    let(:submission) { create(:fitness_test_submission) }

    it "returns all exercise types" do
      expect(submission.exercise_types).to contain_exactly("pushup", "squat", "pullup")
    end
  end

  describe "#store_analysis!" do
    let(:submission) { create(:fitness_test_submission) }
    let(:analysis) { { "rep_count" => 15, "form_score" => 80 } }

    it "stores analysis for exercise type" do
      submission.store_analysis!("pushup", analysis)
      expect(submission.analysis_for("pushup")).to eq(analysis)
    end
  end
end
