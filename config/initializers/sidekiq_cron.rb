# frozen_string_literal: true

# Sidekiq-Cron scheduled jobs configuration
# Jobs run automatically on the specified schedule

if defined?(Sidekiq)
  Sidekiq.configure_server do |config|
    config.on(:startup) do
      schedule = {}

      # TestFlight feedback polling (every 5 minutes)
      if AppStoreConnectService.configured?
        schedule["poll_testflight_feedback"] = {
          "cron" => "*/5 * * * *",
          "class" => "PollTestflightFeedbackJob",
          "queue" => "default",
          "description" => "Poll App Store Connect for new TestFlight feedback"
        }
      end

      # NOTE: Video processing jobs disabled - pipeline complete
      # - embedding: 100% (5,174/5,174)
      # - pending videos: 0

      Sidekiq::Cron::Job.load_from_hash!(schedule) if schedule.any?
    end
  end
end
