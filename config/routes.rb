Rails.application.routes.draw do
  # GraphQL API endpoint
  post "/graphql", to: "graphql#execute"

  # Health check endpoints for monitoring and orchestration
  # These are excluded from rate limiting and authentication
  scope "/health", controller: :health do
    get "/", action: :show       # Basic liveness: GET /health
    get "/ready", action: :ready # Readiness probe: GET /health/ready
    get "/live", action: :live   # Liveness probe: GET /health/live
    get "/details", action: :details # Detailed info: GET /health/details
  end

  # Legacy health check endpoint (Rails default)
  get "up" => "rails/health#show", as: :rails_health_check

  # Admin endpoints (protected by token)
  scope "/admin", controller: :admin do
    get "/chat", action: :chat_ui
    post "/chat", action: :chat_send
    get "/test_user_info", action: :test_user_info
    get "/test_users", action: :test_users_list
    post "/reset_test_user", action: :reset_test_user
    post "/delete_test_routines", action: :delete_test_routines
    post "/normalize_exercises", action: :normalize_exercises
    get "/exercise_stats", action: :exercise_stats
    get "/exercise_data_status", action: :exercise_data_status
    post "/sync_exercise_knowledge", action: :sync_exercise_knowledge
    post "/test_routine_generator", action: :test_routine_generator
    get "/analyze_exercises", action: :analyze_exercises
    post "/deactivate_suspicious_exercises", action: :deactivate_suspicious_exercises
    post "/deactivate_exercises_without_video", action: :deactivate_exercises_without_video
    post "/reanalyze_videos", action: :reanalyze_videos
    post "/stop_reanalysis", action: :stop_reanalysis
    get "/reanalyze_status", action: :reanalyze_status
    post "/ai_cleanup_knowledge", action: :ai_cleanup_knowledge
    get "/sample_knowledge", action: :sample_knowledge
    get "/list_knowledge", action: :list_knowledge
    delete "/delete_chunks", action: :delete_chunks
    get "/simulate_beginner", action: :simulate_beginner
    get "/simulate_all_levels", action: :simulate_all_levels
    post "/tag_knowledge_levels", action: :tag_knowledge_levels
    post "/seed_exercises", action: :seed_exercises
    get "/test_subtitle_extraction", action: :test_subtitle_extraction
    post "/test_knowledge_extraction", action: :test_knowledge_extraction
    post "/import_program_knowledge", action: :import_program_knowledge
    post "/import_knowledge_chunk", action: :import_knowledge_chunk
    get "/embedding_status", action: :embedding_status
    post "/generate_embeddings", action: :generate_embeddings
    post "/test_search", action: :test_search
    get "/check_pgvector", action: :check_pgvector
    post "/extract_transcripts", action: :extract_transcripts
    get "/transcript_status", action: :transcript_status
    get "/channel_status", action: :channel_status
    post "/bulk_import_videos", action: :bulk_import_videos
    post "/seed_channels", action: :seed_channels
    post "/toggle_channel", action: :toggle_channel
    post "/stop_transcript_extraction", action: :stop_transcript_extraction
    get "/worker_status", action: :worker_status
  end

  # Defines the root path route ("/")
  # root "posts#index"
end
