require "active_support/core_ext/integer/time"

Rails.application.configure do
  # Cache can be swapped for Redis/memcached in production; memory store keeps
  # the single-node deployment simple (documented tradeoff in the README).
  config.cache_store = :memory_store, { size: 256.megabytes }

  config.eager_load = true

  config.consider_all_requests_local = false
  config.action_dispatch.show_exceptions = true

  config.public_file_server.enabled = ENV["RAILS_SERVE_STATIC_FILES"].present?

  config.active_support.deprecation = :notify

  # Production secret must come from the environment.
  config.secret_key_base = ENV.fetch("SECRET_KEY_BASE")

  # Structured JSON logs to stdout (12-factor style, container friendly).
  config.logger = ActiveSupport::Logger.new($stdout)
  config.log_level = :info
end
