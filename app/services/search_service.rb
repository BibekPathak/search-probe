# Orchestrates a search through the ExtractionPlanner with caching on top.
#
# Public entry points:
#   call(query:, engine:, request_id:, context:, force_refresh:)
#     - validates params, creates a Search, then performs it (sync endpoint)
#   perform(search:, request_id:, context:, force_refresh:)
#     - runs a *persisted* Search through the planner (async jobs)
#
# Caching: identical query + engine answers are served from Rails.cache and
# still persisted as lightweight Search/SearchResult rows so the dashboard,
# metrics and SERP-diff stay coherent.
class SearchService
  Outcome = Struct.new(:query, :engine, :results, :cached, :latency_ms,
                       :strategy, :attempts, :search, keyword_init: true)

  DEFAULT_ENGINE = "google"

  def initialize(planner: nil)
    @planner = planner || ExtractionPlanner.default
  end

  def call(query:, engine: nil, request_id: nil, context: {}, force_refresh: false)
    normalized_query = query.to_s.strip
    normalized_engine = engine.to_s.strip.presence || DEFAULT_ENGINE
    validate!(normalized_query, normalized_engine)

    search = Search.create!(query: normalized_query, engine: normalized_engine, status: "running")

    outcome = perform(search: search, request_id: request_id, context: context, force_refresh: force_refresh)

    unless outcome.cached || outcome.search.status == "completed"
      raise Errors::ExtractionFailed.new(
        error_type: outcome.search.error_type,
        message: "Extraction failed (#{outcome.search.error_type})"
      )
    end

    outcome
  rescue Errors::Error
    raise
  rescue Mongoid::Errors::MongoidError, Mongo::Error => e
    raise Errors::ExtractionFailed.new(error_type: "unknown", message: "Persistence error: #{e.class}")
  end

  def perform(search:, request_id: nil, context: {}, force_refresh: false)
    return completed_outcome(search) if search.status == "completed"

    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    search.update!(status: "running") unless search.status == "running"

    cacheable = !force_refresh && context[:simulate].blank? && context[:simulate_order].blank?

    if cacheable && (cached_results = SearchCache.read(query: search.query, engine: search.engine))
      latency = elapsed_ms(started)
      persist_results(search, cached_results)
      search.update!(status: "completed", cache_hit: true, strategy: "cache", latency_ms: latency)
      log_search(search, request_id, cached: true, latency_ms: latency)
      return outcome(search, cached_results, cached: true, latency_ms: latency, strategy: "cache", attempts: 0)
    end

    outcome = @planner.call(
      query: search.query,
      engine: search.engine,
      search: search,
      request_id: request_id,
      context: context
    )

    extraction = outcome.extraction
    if extraction.success?
      persist_results(search, extraction.results)
      SearchCache.write(query: search.query, engine: search.engine, results: extraction.results) if cacheable
      latency = elapsed_ms(started)
      search.update!(status: "completed", cache_hit: false, strategy: extraction.strategy, latency_ms: latency)
      log_search(search, request_id, cached: false, latency_ms: latency)
      outcome(search, extraction.results, cached: false, latency_ms: latency,
              strategy: extraction.strategy, attempts: outcome.attempts.length)
    else
      latency = elapsed_ms(started)
      search.update!(status: "failed", error_type: extraction.error_type, latency_ms: latency)
      log_search(search, request_id, cached: false, latency_ms: latency, error_type: extraction.error_type)
      outcome(search, [], cached: false, latency_ms: latency,
              strategy: extraction.strategy, attempts: outcome.attempts.length)
    end
  end

  private

  def outcome(search, results, cached:, latency_ms:, strategy:, attempts:)
    Outcome.new(
      query: search.query,
      engine: search.engine,
      results: results,
      cached: cached,
      latency_ms: latency_ms,
      strategy: strategy,
      attempts: attempts,
      search: search
    )
  end

  def completed_outcome(search)
    outcome(search, search.search_results.order_by(position: :asc).map(&:to_api_hash),
            cached: search.cache_hit, latency_ms: search.latency_ms, strategy: search.strategy,
            attempts: search.extraction_attempts.count)
  end

  def validate!(query, engine)
    if query.empty?
      raise Errors::ValidationError.new("missing_query", "Parameter q is required and cannot be blank.")
    end
    if query.length > 500
      raise Errors::ValidationError.new("query_too_long", "Parameter q must be 500 characters or fewer.")
    end
    return if Search::ENGINES.include?(engine)

    raise Errors::UnsupportedEngine.new(engine)
  end

  def persist_results(search, results)
    docs = results.map do |result|
      { search_id: search.id, **result }
    end
    SearchResult.collection.insert_many(docs)
  end

  def elapsed_ms(started)
    ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started) * 1000).round
  end

  def log_search(search, request_id, cached:, latency_ms:, error_type: nil)
    StructuredLog.emit(
      cached ? "search.cache_hit" : "search.#{error_type ? 'failed' : 'completed'}",
      {
        request_id: request_id,
        search_id: search.id.to_s,
        query: search.query,
        engine: search.engine,
        cached: cached,
        latency_ms: latency_ms,
        strategy: search.strategy,
        error_type: error_type
      }.compact
    )
  end
end
