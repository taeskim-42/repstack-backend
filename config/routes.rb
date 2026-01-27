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
    post "/reanalyze_videos", action: :reanalyze_videos
    post "/stop_reanalysis", action: :stop_reanalysis
    get "/reanalyze_status", action: :reanalyze_status
    post "/ai_cleanup_knowledge", action: :ai_cleanup_knowledge
    get "/sample_knowledge", action: :sample_knowledge
    delete "/delete_chunks", action: :delete_chunks
    get "/simulate_beginner", action: :simulate_beginner
    get "/simulate_all_levels", action: :simulate_all_levels
    post "/tag_knowledge_levels", action: :tag_knowledge_levels
    post "/seed_exercises", action: :seed_exercises
    get "/test_subtitle_extraction", action: :test_subtitle_extraction
    post "/test_knowledge_extraction", action: :test_knowledge_extraction
  end

  # Defines the root path route ("/")
  # root "posts#index"
end
