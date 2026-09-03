require "active_support/core_ext/integer/time"

Rails.application.configure do
  # Memory-backed cache so request specs can exercise cache-hit semantics.
  config.cache_store = :memory_store, { size: 8.megabytes }

  # Queued jobs run inline in tests via perform_enqueued_jobs.
  config.active_job.queue_adapter = :test

  config.action_controller.perform_caching = false

  config.eager_load = ENV["CI"].present?

  config.public_file_server.enabled = true
  config.public_file_server.headers = { "Cache-Control" => "public, max-age=3600" }

  config.consider_all_requests_local = true
  config.action_dispatch.show_exceptions = :rescuable
  config.action_controller.allow_forgery_protection = false

  config.active_support.deprecation = :stderr

  config.secret_key_base = "test_secret_key_base_0123456789abcdef"

  config.log_level = ENV.fetch("RAILS_LOG_LEVEL", "warn")
  config.logger = ActiveSupport::Logger.new($stdout)
end
