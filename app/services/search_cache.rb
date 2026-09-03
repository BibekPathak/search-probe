# Cache for identical query + engine responses.
#
# Key:  search:{engine}:{normalized_query}
# TTL:  configurable (default 5 minutes, CACHE_TTL env)
# Bypass: force_refresh=true on the API (handled by the caller)
#
# Only successful, un-simulated extractions are cached so demo failure
# scenarios always exercise the planner.
class SearchCache
  KEY_PREFIX = "search"

  def self.read(query:, engine:)
    Rails.cache.read(key(query: query, engine: engine))
  end

  def self.write(query:, engine:, results:)
    Rails.cache.write(key(query: query, engine: engine), results, expires_in: ttl)
  end

  def self.key(query:, engine:)
    "#{KEY_PREFIX}:#{engine}:#{query.to_s.strip.downcase}"
  end

  def self.ttl
    Rails.application.config.x.cache_ttl
  end
end
