Rails.application.routes.draw do
  # Liveness / readiness for orchestrators and healthchecks.
  get "health", to: "health#show"

  # Simulated search-engine endpoint used by the extraction stack.
  get "simulator/:engine", to: "simulator#show", engine: /google|bing|duckduckgo/

  # Public dashboard (development convenience; reads live metrics).
  get "dashboard", to: "dashboard#show"

  # --- JSON API v1 (all endpoints below require X-API-Key) ---
  namespace :api do
    namespace :v1 do
      # Synchronous search: GET /api/v1/search?q=...&engine=google&force_refresh=true
      get "search", to: "search#show"

      # Asynchronous search lifecycle.
      resources :searches, only: %i[create show] do
        member do
          get "diff"
        end
      end

      # Aggregated operational metrics.
      get "metrics", to: "metrics#index"
    end
  end

  # Everything else is 404 for this API-only project.
  root to: redirect("/dashboard")
end
