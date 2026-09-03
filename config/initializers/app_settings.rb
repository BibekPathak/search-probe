# Central, environment-driven settings used across services/controllers.
# Each key has a sane default so the app runs with `docker compose up` and no
# extra configuration. Documented in the README environment-variable table.

Rails.application.configure do
  config.x.app = ActiveSupport::OrderedOptions.new
  config.x.app.name = "SearchProbe"

  # Where the simulated search engines live. In Docker this must be reachable
  # both from the backend itself and from the Playwright worker, hence the
  # docker-network hostname (http://backend:3000).
  config.x.simulator_base_url = ENV.fetch("SIMULATOR_BASE_URL", "http://localhost:3000")

  # Playwright extraction worker.
  config.x.browser_worker_url = ENV.fetch("BROWSER_WORKER_URL", "http://localhost:8001")

  # Cache TTL (seconds) for identical query+engine responses.
  config.x.cache_ttl = ENV.fetch("CACHE_TTL", "300").to_i

  # Extraction planner knobs.
  config.x.max_attempts = ENV.fetch("MAX_ATTEMPTS", "3").to_i
  config.x.request_timeout_seconds = ENV.fetch("REQUEST_TIMEOUT_SECONDS", "5").to_i

  # API rate limiting: requests per minute per API key (or IP for unauthenticated probes).
  config.x.rate_limit_per_minute = ENV.fetch("RATE_LIMIT_PER_MINUTE", "100").to_i
end
