# The unit of work every extractor returns. Common interface between the HTTP
# and browser strategies and the planner, so SearchService never talks to a
# concrete scraper. Expected failures are data, not exceptions.
class ExtractionResult
  attr_reader :success, :strategy, :results, :latency_ms,
              :http_status, :error_type, :error_message, :metadata

  def initialize(success:, strategy:, results: [], latency_ms: 0,
                 http_status: nil, error_type: nil, error_message: nil, metadata: {})
    @success = success
    @strategy = strategy
    @results = results
    @latency_ms = latency_ms
    @http_status = http_status
    @error_type = error_type
    @error_message = error_message
    @metadata = metadata
  end

  def self.success(strategy:, results:, latency_ms:, http_status:, metadata: {})
    new(success: true, strategy: strategy, results: results, latency_ms: latency_ms,
        http_status: http_status, metadata: metadata)
  end

  def self.failure(strategy:, error_type:, error_message:, latency_ms: 0, http_status: nil, metadata: {})
    new(success: false, strategy: strategy, latency_ms: latency_ms, http_status: http_status,
        error_type: error_type, error_message: error_message, metadata: metadata)
  end

  def success?
    success == true
  end

  def failure?
    !success?
  end
end
