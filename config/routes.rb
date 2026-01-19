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

  # Defines the root path route ("/")
  # root "posts#index"
end
