# HTTP extraction strategy.
#
# Cheap and fast: fetch the (simulated) engine page with a plain HTTP client,
# parse the HTML, and normalize. Everything is expressed through the common
# ExtractionResult interface so the planner can mix strategies freely.
class HttpExtractor
  STRATEGY = "http"

  # Status codes the strategy must reason about:
  #   200            -> parse + return results (or captcha/parse failure)
  #   403            -> blocked
  #   429            -> rate_limited
  #   5xx / timeout  -> transient, server-side (retryable)
  def extract(query:, engine:, context: {})
    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    url = build_url(query: query, engine: engine)

    response = HttpFetcher.new.get(url, timeout_seconds: timeout_seconds)
    latency = elapsed_ms(started)

    interpret(response, latency: latency)
  rescue Net::OpenTimeout, Net::ReadTimeout, Timeout::Error, Errno::ETIMEDOUT
    ExtractionResult.failure(
      strategy: STRATEGY,
      error_type: "timeout",
      error_message: "Request to #{engine} timed out after #{timeout_seconds}s",
      latency_ms: elapsed_ms(started)
    )
  rescue SocketError, Errno::ECONNREFUSED, Errno::ECONNRESET, EOFError, IOError => e
    ExtractionResult.failure(
      strategy: STRATEGY,
      error_type: "network_error",
      error_message: e.class.name,
      latency_ms: elapsed_ms(started)
    )
  rescue Errors::ExtractionFailed => e
    ExtractionResult.failure(
      strategy: STRATEGY,
      error_type: e.error_type,
      error_message: e.error_message,
      latency_ms: elapsed_ms(started)
    )
  rescue StandardError => e
    ExtractionResult.failure(
      strategy: STRATEGY,
      error_type: "unknown",
      error_message: "#{e.class}: #{e.message}",
      latency_ms: elapsed_ms(started)
    )
  end

  private

  def build_url(query:, engine:)
    base = Rails.application.config.x.simulator_base_url
    count = Simulator::SerpBuilder::DEFAULT_COUNT
    "#{base}/simulator/#{engine}?q=#{CGI.escape(query)}&count=#{count}"
  end

  def interpret(response, latency:)
    case response.status
    when 403
      failure("blocked", "Engine refused the request (HTTP 403)", latency, response.status)
    when 429
      failure("rate_limited", "Engine rate limited the request (HTTP 429)", latency, response.status)
    when 401
      failure("blocked", "Engine requires authentication (HTTP 401)", latency, response.status)
    when 408
      failure("timeout", "Engine request timed out (HTTP 408)", latency, response.status)
    when 500..599
      failure("unknown", "Engine returned an internal error (HTTP #{response.status})", latency, response.status)
    else
      interpret_ok(response.body, latency: latency, status: response.status)
    end
  end

  def interpret_ok(body, latency:, status:)
    return failure("captcha", "Engine presented a CAPTCHA challenge", latency, status) if SerpParser.captcha?(body)

    raw = SerpParser.parse(body)
    results = ResultNormalizer.normalize_results(raw)

    if results.empty?
      failure("parse_error", "No organic results found in engine response", latency, status)
    else
      ExtractionResult.success(
        strategy: STRATEGY,
        results: results,
        latency_ms: latency,
        http_status: status,
        metadata: { result_count: results.size }
      )
    end
  end

  def failure(error_type, message, latency, http_status)
    ExtractionResult.failure(
      strategy: STRATEGY,
      error_type: error_type,
      error_message: message,
      latency_ms: latency,
      http_status: http_status
    )
  end

  def timeout_seconds
    Rails.application.config.x.request_timeout_seconds
  end

  def elapsed_ms(started)
    ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started) * 1000).round
  end
end
