# frozen_string_literal: true

require "rails_helper"

RSpec.describe Mutations::SubmitFeedback, type: :graphql do
  let(:user) { create(:user, :with_profile) }
  let(:routine) { create(:workout_routine, user: user) }
  let(:session) { create(:workout_session, :completed, user: user) }
  let(:workout_record) { create(:workout_record, user: user, workout_session: session) }

  let(:mutation) do
    <<~GRAPHQL
      mutation SubmitFeedback($input: SubmitFeedbackInput!) {
        submitFeedback(input: $input) {
          success
          feedback {
            id
            rating
            feedbackType
          }
          analysis {
            insights
            adaptations
            nextWorkoutRecommendations
          }
          error
        }
      }
    GRAPHQL
  end

  let(:feedback_data) do
    {
      workoutRecordId: workout_record.id.to_s,
      routineId: routine.id.to_s,
      feedbackType: "DIFFICULTY",
      rating: 4,
      feedback: "운동이 적당히 힘들었습니다.",
      suggestions: ["좀 더 무거운 중량 추천"],
      wouldRecommend: true
    }
  end

  describe "when authenticated" do
    context "with valid input and successful AI analysis" do
      before do
        allow(AiTrainer::FeedbackService).to receive(:analyze_from_input).and_return({
          success: true,
          insights: ["사용자의 근력이 향상되고 있습니다."],
          adaptations: ["다음 주 중량 5% 증가"],
          next_workout_recommendations: ["벤치프레스 세트 수 증가 권장"]
        })
      end

      it "submits feedback successfully" do
        response = execute_graphql(
          query: mutation,
          variables: { input: { input: feedback_data } },
          context: { current_user: user }
        )
        data = response["data"]["submitFeedback"]

        expect(data["success"]).to be true
        expect(data["error"]).to be_nil
      end

      it "creates feedback record" do
        expect {
          execute_graphql(
            query: mutation,
            variables: { input: { input: feedback_data } },
            context: { current_user: user }
          )
        }.to change(WorkoutFeedback, :count).by(1)
      end

      it "returns feedback details" do
        response = execute_graphql(
          query: mutation,
          variables: { input: { input: feedback_data } },
          context: { current_user: user }
        )
        data = response["data"]["submitFeedback"]

        expect(data["feedback"]["rating"]).to eq(4)
        expect(data["feedback"]["feedbackType"]).to eq("DIFFICULTY")
      end

      it "returns AI analysis" do
        response = execute_graphql(
          query: mutation,
          variables: { input: { input: feedback_data } },
          context: { current_user: user }
        )
        data = response["data"]["submitFeedback"]

        expect(data["analysis"]["insights"]).to include("사용자의 근력이 향상되고 있습니다.")
        expect(data["analysis"]["adaptations"]).to include("다음 주 중량 5% 증가")
        expect(data["analysis"]["nextWorkoutRecommendations"]).to include("벤치프레스 세트 수 증가 권장")
      end
    end

    context "when AI analysis fails" do
      before do
        allow(AiTrainer::FeedbackService).to receive(:analyze_from_input).and_return({
          success: false,
          error: "AI 서비스 일시 오류"
        })
      end

      it "still saves feedback successfully" do
        response = execute_graphql(
          query: mutation,
          variables: { input: { input: feedback_data } },
          context: { current_user: user }
        )
        data = response["data"]["submitFeedback"]

        expect(data["success"]).to be true
        expect(data["feedback"]).to be_present
      end

      it "returns nil analysis" do
        response = execute_graphql(
          query: mutation,
          variables: { input: { input: feedback_data } },
          context: { current_user: user }
        )
        data = response["data"]["submitFeedback"]

        expect(data["analysis"]).to be_nil
      end

      it "creates feedback record in database" do
        expect {
          execute_graphql(
            query: mutation,
            variables: { input: { input: feedback_data } },
            context: { current_user: user }
          )
        }.to change(WorkoutFeedback, :count).by(1)
      end
    end

    context "with different feedback types" do
      %w[EFFECTIVENESS ENJOYMENT TIME OTHER].each do |feedback_type|
        it "handles #{feedback_type} feedback type" do
          allow(AiTrainer::FeedbackService).to receive(:analyze_from_input).and_return({ success: true, insights: [] })

          type_data = feedback_data.merge(feedbackType: feedback_type)

          response = execute_graphql(
            query: mutation,
            variables: { input: { input: type_data } },
            context: { current_user: user }
          )
          data = response["data"]["submitFeedback"]

          expect(data["success"]).to be true
          expect(data["feedback"]["feedbackType"]).to eq(feedback_type)
        end
      end
    end

    context "with different ratings" do
      (1..5).each do |rating|
        it "accepts rating of #{rating}" do
          allow(AiTrainer::FeedbackService).to receive(:analyze_from_input).and_return({ success: true, insights: [] })

          rating_data = feedback_data.merge(rating: rating)

          response = execute_graphql(
            query: mutation,
            variables: { input: { input: rating_data } },
            context: { current_user: user }
          )
          data = response["data"]["submitFeedback"]

          expect(data["success"]).to be true
          expect(data["feedback"]["rating"]).to eq(rating)
        end
      end
    end

    context "with optional suggestions" do
      it "works without suggestions" do
        allow(AiTrainer::FeedbackService).to receive(:analyze_from_input).and_return({ success: true, insights: [] })

        data_without_suggestions = feedback_data.except(:suggestions)

        response = execute_graphql(
          query: mutation,
          variables: { input: { input: data_without_suggestions } },
          context: { current_user: user }
        )
        data = response["data"]["submitFeedback"]

        expect(data["success"]).to be true
      end

      it "handles multiple suggestions" do
        allow(AiTrainer::FeedbackService).to receive(:analyze_from_input).and_return({ success: true, insights: [] })

        multi_suggestion_data = feedback_data.merge(suggestions: ["첫 번째 제안", "두 번째 제안", "세 번째 제안"])

        response = execute_graphql(
          query: mutation,
          variables: { input: { input: multi_suggestion_data } },
          context: { current_user: user }
        )
        data = response["data"]["submitFeedback"]

        expect(data["success"]).to be true
      end
    end

    context "with would_recommend variations" do
      it "handles would_recommend false" do
        allow(AiTrainer::FeedbackService).to receive(:analyze_from_input).and_return({ success: true, insights: [] })

        not_recommend_data = feedback_data.merge(wouldRecommend: false)

        response = execute_graphql(
          query: mutation,
          variables: { input: { input: not_recommend_data } },
          context: { current_user: user }
        )
        data = response["data"]["submitFeedback"]

        expect(data["success"]).to be true
      end
    end

    context "when unexpected error occurs" do
      before do
        allow(WorkoutFeedback).to receive(:create!).and_raise(StandardError, "Unexpected error")
      end

      it "returns generic error message" do
        response = execute_graphql(
          query: mutation,
          variables: { input: { input: feedback_data } },
          context: { current_user: user }
        )
        data = response["data"]["submitFeedback"]

        expect(data["success"]).to be false
        expect(data["error"]).to eq("Failed to submit feedback")
      end
    end
  end

  describe "when not authenticated" do
    it "returns authentication error" do
      result = RepstackBackendSchema.execute(
        mutation,
        variables: { input: { input: feedback_data } },
        context: { current_user: nil }
      )

      data = result["data"]["submitFeedback"]
      expect(data["success"]).to be false
      expect(data["error"]).to be_present
    end
  end
end
