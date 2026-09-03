# Puma configuration for SearchProbe.
max_threads_count = ENV.fetch("RAILS_MAX_THREADS", 5)
min_threads_count = ENV.fetch("RAILS_MIN_THREADS", max_threads_count)
threads min_threads_count, max_threads_count

port ENV.fetch("PORT", 3000)
environment ENV.fetch("RAILS_ENV", "development")

# Workers disabled by default in dev to keep memory + Mongo connections low.
if ENV.fetch("RAILS_ENV", "development") == "production" && ENV.fetch("WEB_CONCURRENCY", "0").to_i.positive?
  workers ENV.fetch("WEB_CONCURRENCY").to_i
end

plugin :tmp_restart
