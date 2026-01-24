# frozen_string_literal: true

require "rails_helper"

RSpec.describe Mutations::CreateFitnessTestUploadUrl, type: :request do
  let(:user) { create(:user) }
  let!(:user_profile) { create(:user_profile, user: user, level_assessed_at: nil) }

  let(:mutation) do
    <<~GQL
      mutation CreateFitnessTestUploadUrl($input: CreateFitnessTestUploadUrlInput!) {
        createFitnessTestUploadUrl(input: $input) {
          uploadUrl
          videoKey
          expiresAt
          errors
        }
      }
    GQL
  end

  describe "when user is authenticated" do
    before do
      allow_any_instance_of(GraphqlController).to receive(:current_user).and_return(user)
    end

    context "when AWS is not configured" do
      before do
        allow(AwsConfig).to receive(:configured?).and_return(false)
      end

      it "returns an error" do
        post "/graphql", params: {
          query: mutation,
          variables: { input: { exerciseType: "pushup" } }
        }

        json = JSON.parse(response.body)
        data = json["data"]["createFitnessTestUploadUrl"]

        expect(data["uploadUrl"]).to be_nil
        expect(data["errors"]).to include("AWS credentials not configured")
      end
    end

    context "when AWS is configured" do
      before do
        allow(AwsConfig).to receive(:configured?).and_return(true)
        allow(AwsConfig).to receive(:s3_client).and_return(double)
        allow(AwsConfig).to receive(:s3_bucket).and_return("test-bucket")

        mock_presigner = double
        allow(Aws::S3::Presigner).to receive(:new).and_return(mock_presigner)
        allow(mock_presigner).to receive(:presigned_url).and_return("https://s3.example.com/presigned-url")
      end

      it "returns upload URL for valid exercise type" do
        post "/graphql", params: {
          query: mutation,
          variables: { input: { exerciseType: "pushup" } }
        }

        json = JSON.parse(response.body)
        data = json["data"]["createFitnessTestUploadUrl"]

        expect(data["uploadUrl"]).to be_present
        expect(data["videoKey"]).to include("fitness-tests/#{user.id}/pushup_")
        expect(data["expiresAt"]).to be_present
        expect(data["errors"]).to be_empty
      end

      it "works for various exercise types" do
        %w[pushup squat pullup bench_press deadlift barbell_squat].each do |exercise_type|
          post "/graphql", params: {
            query: mutation,
            variables: { input: { exerciseType: exercise_type } }
          }

          json = JSON.parse(response.body)
          data = json["data"]["createFitnessTestUploadUrl"]

          expect(data["errors"]).to be_empty
        end
      end
    end

    context "when user already has level assessed" do
      before do
        user_profile.update!(level_assessed_at: Time.current)
      end

      it "returns an error" do
        post "/graphql", params: {
          query: mutation,
          variables: { input: { exerciseType: "pushup" } }
        }

        json = JSON.parse(response.body)
        data = json["data"]["createFitnessTestUploadUrl"]

        expect(data["uploadUrl"]).to be_nil
        expect(data["errors"]).to include("이미 레벨이 측정되었습니다. 레벨 변경은 승급 테스트를 통해 진행해주세요.")
      end
    end

    context "with invalid content type" do
      before do
        allow(AwsConfig).to receive(:configured?).and_return(true)
      end

      it "returns an error for unsupported content type" do
        post "/graphql", params: {
          query: mutation,
          variables: { input: { exerciseType: "pushup", contentType: "video/avi" } }
        }

        json = JSON.parse(response.body)
        data = json["data"]["createFitnessTestUploadUrl"]

        expect(data["uploadUrl"]).to be_nil
        expect(data["errors"]).to include("지원하지 않는 파일 형식입니다.")
      end
    end

    context "with invalid exercise type format" do
      before do
        allow(AwsConfig).to receive(:configured?).and_return(true)
      end

      it "returns an error" do
        post "/graphql", params: {
          query: mutation,
          variables: { input: { exerciseType: "INVALID-TYPE!" } }
        }

        json = JSON.parse(response.body)
        data = json["data"]["createFitnessTestUploadUrl"]

        expect(data["uploadUrl"]).to be_nil
        expect(data["errors"]).to include("잘못된 운동 타입입니다.")
      end
    end
  end

  describe "when user is not authenticated" do
    it "returns an authentication error" do
      post "/graphql", params: {
        query: mutation,
        variables: { input: { exerciseType: "pushup" } }
      }

      json = JSON.parse(response.body)
      data = json["data"]["createFitnessTestUploadUrl"]

      expect(data["uploadUrl"]).to be_nil
      expect(data["errors"]).to include("인증이 필요합니다.")
    end
  end
end
