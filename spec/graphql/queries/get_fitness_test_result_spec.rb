# frozen_string_literal: true

require "rails_helper"

RSpec.describe Queries::GetFitnessTestResult, type: :request do
  let(:user) { create(:user) }
  let!(:user_profile) { create(:user_profile, user: user) }

  let(:query_by_id) do
    <<~GQL
      query GetFitnessTestResult($submissionId: ID) {
        getFitnessTestResult(submissionId: $submissionId) {
          id
          jobId
          status
          fitnessScore
          assignedLevel
          assignedTier
          message
          recommendations
          videos {
            exerciseType
            videoKey
          }
          analyses {
            exerciseType
            repCount
            formScore
            issues
            feedback
          }
          errorMessage
        }
      }
    GQL
  end

  let(:query_by_job_id) do
    <<~GQL
      query GetFitnessTestResult($jobId: String) {
        getFitnessTestResult(jobId: $jobId) {
          id
          jobId
          status
        }
      }
    GQL
  end

  describe "when user is authenticated" do
    before do
      allow_any_instance_of(GraphqlController).to receive(:current_user).and_return(user)
    end

    context "with a pending submission" do
      let!(:submission) { create(:fitness_test_submission, user: user, status: "pending") }

      it "returns submission status" do
        post "/graphql", params: { query: query_by_id, variables: { submissionId: submission.id } }

        json = JSON.parse(response.body)
        data = json["data"]["getFitnessTestResult"]

        expect(data["id"]).to eq(submission.id.to_s)
        expect(data["status"]).to eq("PENDING")
        expect(data["fitnessScore"]).to be_nil
        expect(data["videos"].size).to eq(3)
      end
    end

    context "with a completed submission" do
      let!(:submission) { create(:fitness_test_submission, :completed, user: user) }

      it "returns full results" do
        post "/graphql", params: { query: query_by_id, variables: { submissionId: submission.id } }

        json = JSON.parse(response.body)
        data = json["data"]["getFitnessTestResult"]

        expect(data["id"]).to eq(submission.id.to_s)
        expect(data["status"]).to eq("COMPLETED")
        expect(data["fitnessScore"]).to eq(75)
        expect(data["assignedLevel"]).to eq(3)
        expect(data["assignedTier"]).to eq("intermediate")
        expect(data["analyses"].size).to eq(3)

        pushup_analysis = data["analyses"].find { |a| a["exerciseType"] == "pushup" }
        expect(pushup_analysis["repCount"]).to eq(20)
        expect(pushup_analysis["formScore"]).to eq(80)
      end
    end

    context "with a failed submission" do
      let!(:submission) { create(:fitness_test_submission, :failed, user: user) }

      it "returns error message" do
        post "/graphql", params: { query: query_by_id, variables: { submissionId: submission.id } }

        json = JSON.parse(response.body)
        data = json["data"]["getFitnessTestResult"]

        expect(data["status"]).to eq("FAILED")
        expect(data["errorMessage"]).to be_present
      end
    end

    context "querying by job_id" do
      let!(:submission) { create(:fitness_test_submission, user: user) }

      it "returns submission" do
        post "/graphql", params: { query: query_by_job_id, variables: { jobId: submission.job_id } }

        json = JSON.parse(response.body)
        data = json["data"]["getFitnessTestResult"]

        expect(data["id"]).to eq(submission.id.to_s)
        expect(data["jobId"]).to eq(submission.job_id)
      end
    end

    context "when submission doesn't exist" do
      it "returns an error" do
        post "/graphql", params: { query: query_by_id, variables: { submissionId: "99999" } }

        json = JSON.parse(response.body)
        expect(json["errors"]).to be_present
        expect(json["errors"].first["message"]).to include("해당 테스트 제출을 찾을 수 없습니다")
      end
    end

    context "when neither submission_id nor job_id provided" do
      let(:query_empty) do
        <<~GQL
          query GetFitnessTestResult {
            getFitnessTestResult {
              id
            }
          }
        GQL
      end

      it "returns an error" do
        post "/graphql", params: { query: query_empty }

        json = JSON.parse(response.body)
        expect(json["errors"]).to be_present
        expect(json["errors"].first["message"]).to include("submission_id 또는 job_id 중 하나는 필수입니다")
      end
    end

    context "when trying to access another user's submission" do
      let(:other_user) { create(:user) }
      let!(:other_submission) { create(:fitness_test_submission, user: other_user) }

      it "returns not found error" do
        post "/graphql", params: { query: query_by_id, variables: { submissionId: other_submission.id } }

        json = JSON.parse(response.body)
        expect(json["errors"]).to be_present
        expect(json["errors"].first["message"]).to include("해당 테스트 제출을 찾을 수 없습니다")
      end
    end
  end

  describe "when user is not authenticated" do
    it "returns an authentication error" do
      post "/graphql", params: { query: query_by_id, variables: { submissionId: "1" } }

      json = JSON.parse(response.body)
      expect(json["errors"]).to be_present
      expect(json["errors"].first["message"]).to include("sign in")
    end
  end
end
