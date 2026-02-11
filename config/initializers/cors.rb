# Be sure to restart your server when you modify this file.

# Avoid CORS issues when API is called from the frontend app.
# Handle Cross-Origin Resource Sharing (CORS) in order to accept cross-origin Ajax requests.

Rails.application.config.middleware.insert_before 0, Rack::Cors do
  allow do
    origins(
      "https://repstack-backend-production.up.railway.app",
      *(Rails.env.development? ? ["http://localhost:3000"] : [])
    )

    resource "*",
      headers: :any,
      methods: [ :get, :post, :put, :patch, :delete, :options, :head ]
  end
end
