# frozen_string_literal: true

# Sidekiq-Cron scheduled jobs configuration
# Jobs run automatically on the specified schedule
#
# NOTE: Disabled until pipeline scripts are ready
# - embedding: 100% 완료 (5,174/5,174)
# - pending videos: 0개

# if defined?(Sidekiq)
#   Sidekiq.configure_server do |config|
#     config.on(:startup) do
#       schedule = {
#         "process_pending_videos" => {
#           "cron" => "*/5 * * * *",
#           "class" => "ProcessPendingVideosJob",
#           "args" => [10],
#           "queue" => "video_analysis",
#           "description" => "Process videos with transcripts that need Claude analysis + embeddings"
#         },
#         "generate_pending_embeddings" => {
#           "cron" => "*/10 * * * *",
#           "class" => "GeneratePendingEmbeddingsJob",
#           "args" => [50],
#           "queue" => "video_analysis",
#           "description" => "Generate embeddings for knowledge chunks that don't have them"
#         }
#       }
#       Sidekiq::Cron::Job.load_from_hash!(schedule)
#     end
#   end
# end
