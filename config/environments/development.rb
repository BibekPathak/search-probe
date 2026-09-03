require "active_support/core_ext/integer/time"

Rails.application.configure do
  # In development, enable response/query caching so `cached: true` behavior is
  # demonstrable locally without a separate cache store.
  config.cache_store = :memory_store, { size: 64.megabytes }
  config.action_controller.perform_caching = true

  config.eager_load = false

  config.consider_all_requests_local = true

  # Dev-only secret key fallback; fine since nothing sensitive runs locally.
  config.secret_key_base = ENV.fetch("SECRET_KEY_BASE", "development_secret_key_base_0123456789abcdef")

  if Rails.root.join("tmp/caching-dev.txt").exist?
    config.action_controller.perform_caching = true
    config.cache_store = :memory_store
  end

  config.hosts.clear

  # Pretty, colored logs in development.
  config.logger = ActiveSupport::Logger.new($stdout)
  config.log_level = :debug
end
