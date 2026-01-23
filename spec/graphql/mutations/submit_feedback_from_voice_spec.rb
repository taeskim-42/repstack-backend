# frozen_string_literal: true

require "rails_helper"

RSpec.describe Mutations::SubmitFeedbackFromVoice, type: :graphql do
  let(:user) { create(:user) }
  let!(:user_profile) { create(:user_profile, user: user) }

  # Mock AiTrainer::FeedbackService responses
  let(:positive_feedback_response) do
    {
      success: true,
      feedback: {
        rating: 4,
        feedback_type: "GENERAL",
        summary: "운동이 좋았습니다",
        would_recommend: true
      },
      insights: [ "좋은 운동이었습니다", "꾸준히 유지하세요" ],
      adaptations: [],
      next_workout_recommendations: [ "같은 강도 유지", "다음 운동도 화이팅" ],
      interpretation: "긍정적인 피드백입니다."
    }
  end

  let(:difficulty_hard_response) do
    {
      success: true,
      feedback: {
        rating: 2,
        feedback_type: "DIFFICULTY",
        summary: "운동이 힘들었습니다",
        would_recommend: true
      },
      insights: [ "난이도가 높았습니다" ],
      adaptations: [ "무게를 줄이세요", "세트 수를 줄이세요" ],
      next_workout_recommendations: [ "가벼운 무게로 시작", "휴식 시간 늘리기" ],
      interpretation: "운동이 힘들었다는 피드백입니다."
    }
  end

  let(:difficulty_easy_response) do
    {
      success: true,
      feedback: {
        rating: 4,
        feedback_type: "GENERAL",
        summary: "운동이 쉬웠습니다",
        would_recommend: true
      },
      insights: [ "난이도가 낮았습니다" ],
      adaptations: [ "무게를 늘리세요", "세트 수를 늘리세요" ],
      next_workout_recommendations: [ "강도 높이기", "새로운 운동 추가" ],
      interpretation: "운동이 쉬웠다는 피드백입니다."
    }
  end

  let(:mutation) do
    <<~GRAPHQL
      mutation SubmitFeedbackFromVoice($voiceText: String!, $routineId: ID) {
        submitFeedbackFromVoice(input: { voiceText: $voiceText, routineId: $routineId }) {
          success
          feedback {
            id
            rating
            feedbackType
            summary
            wouldRecommend
          }
          analysis {
            insights
            adaptations
            nextWorkoutRecommendations
          }
          interpretation
          error
        }
      }
    GRAPHQL
  end

  describe "when authenticated" do
    context "with positive feedback" do
      it "analyzes satisfaction" do
        allow(AiTrainer::FeedbackService).to receive(:analyze_from_voice).and_return(positive_feedback_response)

        result = execute_graphql(
          query: mutation,
          variables: { voiceText: "오늘 운동 정말 좋았어요! 만족스러웠습니다" },
          context: { current_user: user }
        )

        data = result["data"]["submitFeedbackFromVoice"]
        expect(data["success"]).to be true
        expect(data["feedback"]["rating"]).to be >= 3
        expect(data["analysis"]["insights"]).to be_an(Array)
        expect(data["error"]).to be_nil
      end
    end

    context "with difficulty feedback" do
      it "analyzes when too hard" do
        allow(AiTrainer::FeedbackService).to receive(:analyze_from_voice).and_return(difficulty_hard_response)

        result = execute_graphql(
          query: mutation,
          variables: { voiceText: "운동이 너무 힘들었어요, 무게가 무거웠어요" },
          context: { current_user: user }
        )

        data = result["data"]["submitFeedbackFromVoice"]
        expect(data["success"]).to be true
        expect(data["feedback"]["feedbackType"]).to eq("DIFFICULTY")
        expect(data["analysis"]["adaptations"]).to be_an(Array)
      end

      it "analyzes when too easy" do
        allow(AiTrainer::FeedbackService).to receive(:analyze_from_voice).and_return(difficulty_easy_response)

        result = execute_graphql(
          query: mutation,
          variables: { voiceText: "운동이 좀 쉬웠어요, 더 할 수 있을 것 같아요" },
          context: { current_user: user }
        )

        data = result["data"]["submitFeedbackFromVoice"]
        expect(data["success"]).to be true
        expect(data["feedback"]["rating"]).to be >= 3
        expect(data["analysis"]["adaptations"]).to be_an(Array)
      end
    end

    context "with English feedback" do
      it "analyzes positive feedback" do
        allow(AiTrainer::FeedbackService).to receive(:analyze_from_voice).and_return(positive_feedback_response)

        result = execute_graphql(
          query: mutation,
          variables: { voiceText: "Great workout today! Really loved it" },
          context: { current_user: user }
        )

        data = result["data"]["submitFeedbackFromVoice"]
        expect(data["success"]).to be true
        expect(data["feedback"]["rating"]).to be >= 3
      end

      it "analyzes difficulty feedback" do
        allow(AiTrainer::FeedbackService).to receive(:analyze_from_voice).and_return(difficulty_hard_response)

        result = execute_graphql(
          query: mutation,
          variables: { voiceText: "The workout was too hard today" },
          context: { current_user: user }
        )

        data = result["data"]["submitFeedbackFromVoice"]
        expect(data["success"]).to be true
        expect(data["feedback"]["feedbackType"]).to eq("DIFFICULTY")
      end
    end

    it "returns next workout recommendations" do
      allow(AiTrainer::FeedbackService).to receive(:analyze_from_voice).and_return(positive_feedback_response)

      result = execute_graphql(
        query: mutation,
        variables: { voiceText: "오늘 운동 괜찮았어요" },
        context: { current_user: user }
      )

      data = result["data"]["submitFeedbackFromVoice"]
      expect(data["success"]).to be true
      expect(data["analysis"]["nextWorkoutRecommendations"]).to be_an(Array)
    end

    it "attempts to save feedback record" do
      allow(AiTrainer::FeedbackService).to receive(:analyze_from_voice).and_return(positive_feedback_response)

      result = execute_graphql(
        query: mutation,
        variables: { voiceText: "운동 좋았어요" },
        context: { current_user: user }
      )

      data = result["data"]["submitFeedbackFromVoice"]
      expect(data["success"]).to be true
      # Feedback ID may be nil if save fails silently, but mutation still succeeds
      expect(data["feedback"]).to be_present
    end

    it "returns interpretation" do
      allow(AiTrainer::FeedbackService).to receive(:analyze_from_voice).and_return(difficulty_hard_response)

      result = execute_graphql(
        query: mutation,
        variables: { voiceText: "오늘 운동 힘들었어요" },
        context: { current_user: user }
      )

      data = result["data"]["submitFeedbackFromVoice"]
      expect(data["interpretation"]).to be_present
    end
  end

  describe "when not authenticated" do
    it "returns authentication error" do
      result = execute_graphql(
        query: mutation,
        variables: { voiceText: "운동 좋았어요" },
        context: { current_user: nil }
      )

      expect(result["errors"]).to be_present
    end
  end
end
