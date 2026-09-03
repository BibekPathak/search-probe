# Abstract base for every extraction strategy (HTTP, browser, future real-engine
# adapters). SearchService and the planner only ever depend on this contract:
#
#   extractor.extract(query:, engine:, context: {}) -> ExtractionResult
#
# Expected failures are *data* (an ExtractionResult with success: false), never
# exceptions -- the planner reasons about error_type, not control flow.
class Extractor
  # Strategy key persisted on ExtractionAttempt (http, browser, ...).
  STRATEGY = nil

  def extract(query:, engine:, context: {})
    raise NotImplementedError, "#{self.class} must implement #extract(query:, engine:, context:)"
  end

  private

  def elapsed_ms(started)
    ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started) * 1000).round
  end

  def success_result(strategy:, results:, latency_ms:, http_status: nil, metadata: {})
    ExtractionResult.success(
      strategy: strategy,
      results: results,
      latency_ms: latency_ms,
      http_status: http_status,
      metadata: metadata
    )
  end

  def failure_result(strategy:, error_type:, error_message:, latency_ms: 0, http_status: nil)
    ExtractionResult.failure(
      strategy: strategy,
      error_type: error_type,
      error_message: error_message,
      latency_ms: latency_ms,
      http_status: http_status
    )
  end
end
