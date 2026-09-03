# Orchestrates a single synchronous search through the ExtractionPlanner.
#
# The service owns lifecycle + persistence; the planner owns the extraction
# policy and records every attempt. Controllers stay untouched by either.
class SearchService
  Outcome = Struct.new(:query, :engine, :results, :cached, :latency_ms,
                       :strategy, :attempts, :search, keyword_init: true)

  DEFAULT_ENGINE = "google"

  def initialize(planner: nil)
    @planner = planner || ExtractionPlanner.default
  end

  def call(query:, engine: nil, request_id: nil, context: {})
    normalized_query = query.to_s.strip
    normalized_engine = engine.to_s.strip.presence || DEFAULT_ENGINE

    validate!(normalized_query, normalized_engine)
    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)

    search = Search.create!(query: normalized_query, engine: normalized_engine, status: "running")

    outcome = @planner.call(
      query: normalized_query,
      engine: normalized_engine,
      search: search,
      request_id: request_id,
      context: context
    )

    extraction = outcome.extraction
    unless extraction.success?
      search.update!(status: "failed", error_type: extraction.error_type)
      raise Errors::ExtractionFailed.new(
        error_type: extraction.error_type,
        message: extraction.error_message,
        http_status: extraction.http_status
      )
    end

    persist_results(search, extraction.results)
    latency = elapsed_ms(started)
    search.update!(status: "completed", strategy: extraction.strategy, latency_ms: latency)

    Outcome.new(
      query: normalized_query,
      engine: normalized_engine,
      results: extraction.results,
      cached: false,
      latency_ms: latency,
      strategy: extraction.strategy,
      attempts: outcome.attempts.length,
      search: search
    )
  rescue Errors::Error
    raise
  rescue Mongoid::Errors::MongoidError, Mongo::Error => e
    raise Errors::ExtractionFailed.new(error_type: "unknown", message: "Persistence error: #{e.class}")
  end

  private

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
end
