# frozen_string_literal: true

require "rails_helper"

RSpec.describe Mutations::SubmitFitnessTestVideos, type: :request do
  let(:user) { create(:user) }
  let!(:user_profile) { create(:user_profile, user: user, level_assessed_at: nil) }

  let(:mutation) do
    <<~GQL
      mutation SubmitFitnessTestVideos($input: SubmitFitnessTestVideosInput!) {
        submitFitnessTestVideos(input: $input) {
          submissionId
          jobId
          status
          errors
        }
      }
    GQL
  end

  let(:valid_input) do
    {
      input: {
        videos: [
          { exerciseType: "pushup", videoKey: "fitness-tests/#{user.id}/pushup_abc123.mp4" },
          { exerciseType: "squat", videoKey: "fitness-tests/#{user.id}/squat_abc123.mp4" },
          { exerciseType: "pullup", videoKey: "fitness-tests/#{user.id}/pullup_abc123.mp4" }
        ]
      }
    }
  end

  describe "when user is authenticated" do
    before do
      allow_any_instance_of(GraphqlController).to receive(:current_user).and_return(user)
      allow(FitnessTestAnalysisJob).to receive(:perform_later)
    end

    context "with valid videos" do
      it "creates a submission" do
        expect {
          post "/graphql", params: { query: mutation, variables: valid_input }
        }.to change(FitnessTestSubmission, :count).by(1)
      end

      it "returns submission details" do
        post "/graphql", params: { query: mutation, variables: valid_input }

        json = JSON.parse(response.body)
        data = json["data"]["submitFitnessTestVideos"]

        expect(data["submissionId"]).to be_present
        expect(data["jobId"]).to be_present
        expect(data["status"]).to eq("PENDING")
        expect(data["errors"]).to be_empty
      end

      it "enqueues analysis job" do
        expect(FitnessTestAnalysisJob).to receive(:perform_later).once

        post "/graphql", params: { query: mutation, variables: valid_input }
      end

      it "stores videos correctly" do
        post "/graphql", params: { query: mutation, variables: valid_input }

        submission = FitnessTestSubmission.last
        expect(submission.exercise_types).to contain_exactly("pushup", "squat", "pullup")
      end
    end

    context "with barbell exercises" do
      let(:barbell_input) do
        {
          input: {
            videos: [
              { exerciseType: "bench_press", videoKey: "fitness-tests/#{user.id}/bench_press_abc123.mp4" },
              { exerciseType: "barbell_squat", videoKey: "fitness-tests/#{user.id}/barbell_squat_abc123.mp4" },
              { exerciseType: "deadlift", videoKey: "fitness-tests/#{user.id}/deadlift_abc123.mp4" }
            ]
          }
        }
      end

      it "accepts barbell exercises" do
        post "/graphql", params: { query: mutation, variables: barbell_input }

        json = JSON.parse(response.body)
        data = json["data"]["submitFitnessTestVideos"]

        expect(data["errors"]).to be_empty
        expect(data["submissionId"]).to be_present
      end
    end

    context "when user already has level assessed" do
      before do
        user_profile.update!(level_assessed_at: Time.current)
      end

      it "returns an error" do
        post "/graphql", params: { query: mutation, variables: valid_input }

        json = JSON.parse(response.body)
        data = json["data"]["submitFitnessTestVideos"]

        expect(data["submissionId"]).to be_nil
        expect(data["errors"]).to include("이미 레벨이 측정되었습니다. 레벨 변경은 승급 테스트를 통해 진행해주세요.")
      end
    end

    context "when user has a pending submission" do
      before do
        create(:fitness_test_submission, user: user, status: "pending")
      end

      it "returns an error" do
        post "/graphql", params: { query: mutation, variables: valid_input }

        json = JSON.parse(response.body)
        data = json["data"]["submitFitnessTestVideos"]

        expect(data["submissionId"]).to be_nil
        expect(data["errors"]).to include("이미 처리 중인 테스트가 있습니다. 완료될 때까지 기다려주세요.")
      end
    end

    context "with invalid video keys" do
      it "rejects keys with wrong format" do
        invalid_input = {
          input: {
            videos: [
              { exerciseType: "pushup", videoKey: "wrong-format/video.mp4" }
            ]
          }
        }

        post "/graphql", params: { query: mutation, variables: invalid_input }

        json = JSON.parse(response.body)
        data = json["data"]["submitFitnessTestVideos"]

        expect(data["submissionId"]).to be_nil
        expect(data["errors"]).to include("pushup 영상 키 형식이 올바르지 않습니다.")
      end
    end

    context "with duplicate exercise types" do
      it "returns an error" do
        duplicate_input = {
          input: {
            videos: [
              { exerciseType: "pushup", videoKey: "fitness-tests/#{user.id}/pushup_1.mp4" },
              { exerciseType: "pushup", videoKey: "fitness-tests/#{user.id}/pushup_2.mp4" }
            ]
          }
        }

        post "/graphql", params: { query: mutation, variables: duplicate_input }

        json = JSON.parse(response.body)
        data = json["data"]["submitFitnessTestVideos"]

        expect(data["submissionId"]).to be_nil
        expect(data["errors"]).to include("중복된 운동 타입이 있습니다.")
      end
    end
  end

  describe "when user is not authenticated" do
    it "returns an authentication error" do
      post "/graphql", params: { query: mutation, variables: valid_input }

      json = JSON.parse(response.body)
      data = json["data"]["submitFitnessTestVideos"]

      expect(data["submissionId"]).to be_nil
      expect(data["errors"]).to include("인증이 필요합니다.")
    end
  end
end
