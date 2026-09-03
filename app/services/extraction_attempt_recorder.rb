# Single place that turns an ExtractionResult into persisted telemetry plus a
# structured log line. Shared by the synchronous SearchService and (later) the
# ExtractionPlanner so every attempt -- success or failure -- is recorded and
# observable exactly once, with the same shape.
class ExtractionAttemptRecorder
  def initialize(logger: StructuredLog)
    @logger = logger
  end

  def call(search:, engine:, extraction:, request_id: nil)
    attempt = ExtractionAttempt.create!(
      search: search,
      engine: engine,
      strategy: extraction.strategy,
      status: extraction.success? ? "success" : "failure",
      http_status: extraction.http_status,
      latency_ms: extraction.latency_ms,
      error_type: extraction.error_type,
      error_message: extraction.error_message
    )

    emit_event(attempt, search, request_id)
    attempt
  end

  private

  attr_reader :logger

  def emit_event(attempt, search, request_id)
    logger.emit(
      "extraction_attempt",
      {
        request_id: request_id,
        search_id: search.id.to_s,
        query: search.query,
        engine: attempt.engine,
        strategy: attempt.strategy,
        latency_ms: attempt.latency_ms,
        success: attempt.status == "success",
        error_type: attempt.error_type,
        http_status: attempt.http_status
      }.compact
    )
  end
end
