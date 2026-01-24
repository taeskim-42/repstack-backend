# frozen_string_literal: true

# Background job for analyzing fitness test videos and calculating results
class FitnessTestAnalysisJob < ApplicationJob
  queue_as :video_analysis

  # Retry configuration
  retry_on StandardError, wait: :polynomially_longer, attempts: 3
  discard_on ActiveRecord::RecordNotFound

  # Main job execution
  # @param submission_id [Integer] FitnessTestSubmission ID
  def perform(submission_id)
    submission = FitnessTestSubmission.find(submission_id)

    Rails.logger.info("[FitnessTestAnalysisJob] Starting analysis for submission #{submission_id}")
    submission.start_processing!

    begin
      # Analyze all videos
      analyses = analyze_all_videos(submission)

      # Extract rep counts from analyses for evaluation
      rep_counts = extract_rep_counts(analyses)

      Rails.logger.info("[FitnessTestAnalysisJob] Video analysis complete - #{rep_counts}")

      # Use FitnessTestService to evaluate (if standard exercises are present)
      user = submission.user
      result = calculate_result(user, analyses, rep_counts)

      # Add video analysis details to result
      result[:video_analyses] = analyses

      # Apply result to user profile if this is initial assessment
      if user.user_profile && user.user_profile.level_assessed_at.nil?
        service = AiTrainer::FitnessTestService.new(user: user)
        if service.apply_to_profile(result)
          Rails.logger.info("[FitnessTestAnalysisJob] Profile updated successfully")
        else
          Rails.logger.warn("[FitnessTestAnalysisJob] Failed to update profile")
        end
      end

      # Mark submission as completed
      submission.complete_with_results!(result)
      Rails.logger.info("[FitnessTestAnalysisJob] Submission #{submission_id} completed successfully")

      # Clean up videos from S3 to save storage costs
      cleanup_videos(submission)

    rescue StandardError => e
      Rails.logger.error("[FitnessTestAnalysisJob] Error processing submission #{submission_id}: #{e.message}")
      Rails.logger.error(e.backtrace.first(10).join("\n"))
      submission.fail_with_error!(e.message)
      raise # Re-raise for retry mechanism
    end
  end

  private

  def analyze_all_videos(submission)
    analyses = {}

    submission.videos.each do |video|
      exercise_type = video["exercise_type"]
      video_key = video["video_key"]

      if video_key.blank?
        Rails.logger.warn("[FitnessTestAnalysisJob] No video key for #{exercise_type}")
        analyses[exercise_type] = fallback_analysis(exercise_type)
        next
      end

      # Generate presigned download URL for Claude Vision
      url_result = PresignedUrlService.generate_download_url(video_key, expires_in: 3600)

      unless url_result[:success]
        Rails.logger.error("[FitnessTestAnalysisJob] Failed to get download URL for #{exercise_type}")
        analyses[exercise_type] = fallback_analysis(exercise_type)
        next
      end

      # Analyze video with Claude Vision
      analysis = VideoAnalysisService.analyze_video(
        video_url: url_result[:download_url],
        exercise_type: exercise_type
      )

      if analysis[:success]
        analyses[exercise_type] = analysis
        submission.store_analysis!(exercise_type, analysis)
      else
        Rails.logger.error("[FitnessTestAnalysisJob] Analysis failed for #{exercise_type}: #{analysis[:error]}")
        analyses[exercise_type] = fallback_analysis(exercise_type)
      end

      # Add small delay between API calls to avoid rate limiting
      sleep(1)
    end

    analyses
  end

  def extract_rep_counts(analyses)
    analyses.transform_values { |a| a[:rep_count] || a["rep_count"] || 0 }
  end

  def calculate_result(user, analyses, rep_counts)
    # Check if we have standard bodyweight exercises for FitnessTestService
    has_pushup = rep_counts.key?("pushup")
    has_squat = rep_counts.key?("squat")
    has_pullup = rep_counts.key?("pullup")

    if has_pushup && has_squat && has_pullup
      # Use standard evaluation
      service = AiTrainer::FitnessTestService.new(user: user)
      result = service.evaluate(
        pushup_count: rep_counts["pushup"],
        squat_count: rep_counts["squat"],
        pullup_count: rep_counts["pullup"]
      )
      result[:form_scores] = analyses.transform_values { |a| a[:form_score] || a["form_score"] || 0 }
      result
    else
      # Custom evaluation for non-standard exercises
      custom_evaluation(analyses)
    end
  end

  def custom_evaluation(analyses)
    # Calculate average form score
    form_scores = analyses.values.map { |a| a[:form_score] || a["form_score"] || 0 }
    avg_form_score = form_scores.sum.to_f / [form_scores.size, 1].max

    # Simple level estimation based on form scores
    level = case avg_form_score
            when 0..40 then 1
            when 41..55 then 2
            when 56..70 then 3
            when 71..80 then 4
            when 81..90 then 5
            else 6
            end

    tier = case level
           when 1..2 then "beginner"
           when 3..4 then "intermediate"
           else "advanced"
           end

    {
      success: true,
      fitness_score: avg_form_score.round,
      total_points: nil,
      max_points: nil,
      assigned_level: level,
      assigned_tier: tier,
      exercise_results: analyses.transform_values do |a|
        {
          count: a[:rep_count] || a["rep_count"] || 0,
          form_score: a[:form_score] || a["form_score"] || 0
        }
      end,
      form_scores: analyses.transform_values { |a| a[:form_score] || a["form_score"] || 0 },
      message: generate_message(tier),
      recommendations: generate_recommendations(analyses)
    }
  end

  def generate_message(tier)
    case tier
    when "beginner"
      "기초 체력 측정이 완료되었습니다! 💪 초급 단계에서 시작합니다."
    when "intermediate"
      "좋은 기초 체력을 보유하고 계시네요! 🔥 중급 단계에서 시작합니다."
    when "advanced"
      "뛰어난 체력입니다! 🏆 고급 단계에서 시작합니다."
    else
      "측정 완료! 맞춤형 훈련을 시작합니다."
    end
  end

  def generate_recommendations(analyses)
    recommendations = []

    analyses.each do |exercise_type, analysis|
      form_score = analysis[:form_score] || analysis["form_score"] || 0
      if form_score < 60
        recommendations << "#{exercise_type} 자세 개선이 필요합니다."
      end
    end

    recommendations << "꾸준한 훈련으로 성장해 나가세요!" if recommendations.empty?
    recommendations
  end

  # Fallback analysis when video analysis fails
  def fallback_analysis(exercise_type)
    {
      success: false,
      exercise_type: exercise_type.to_s,
      rep_count: 0,
      form_score: 0,
      issues: ["영상 분석에 실패했습니다."],
      feedback: "영상을 다시 업로드해 주세요."
    }
  end

  # Delete videos from S3 after analysis to save storage costs
  def cleanup_videos(submission)
    return unless AwsConfig.configured?

    submission.all_video_keys.each do |key|
      next if key.blank?

      AwsConfig.s3_client.delete_object(
        bucket: AwsConfig.s3_bucket,
        key: key
      )
      Rails.logger.info("[FitnessTestAnalysisJob] Deleted video: #{key}")
    rescue Aws::S3::Errors::ServiceError => e
      Rails.logger.warn("[FitnessTestAnalysisJob] Failed to delete #{key}: #{e.message}")
    end
  end
end
