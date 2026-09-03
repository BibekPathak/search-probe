# Orchestrates a single synchronous search.
#
# Current shape (Phase 2): one HTTP attempt, persisted + logged via the attempt
# recorder, with normalized results. Later phases slot the ExtractionPlanner,
# cache lookups and background jobs in behind this same facade so the
# controllers stay untouched.
class SearchService
  Outcome = Struct.new(:query, :engine, :results, :cached, :latency_ms,
                       :strategy, :attempts, :search, keyword_init: true)

  DEFAULT_ENGINE = "google"

  def initialize(extractor: nil, recorder: nil)
    @extractor = extractor || HttpExtractor.new
    @recorder = recorder || ExtractionAttemptRecorder.new
  end

  def call(query:, engine: nil, request_id: nil)
    normalized_query = query.to_s.strip
    normalized_engine = engine.to_s.strip.presence || DEFAULT_ENGINE

    validate!(normalized_query, normalized_engine)
    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)

    search = Search.create!(query: normalized_query, engine: normalized_engine, status: "running")

    extraction = @extractor.extract(query: normalized_query, engine: normalized_engine)
    @recorder.call(search: search, engine: normalized_engine, extraction: extraction, request_id: request_id)

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
      attempts: search.extraction_attempts.count,
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
