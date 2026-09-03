# HTTP extraction strategy.
#
# Cheap and fast: fetch the engine page with a plain HTTP client, parse it, and
# normalize. Where the request goes and how the bytes become raw results is
# decided by EngineRegistry -> Provider (simulator by default; Bing RSS/HTML
# when opted in via LIVE_ENGINES). Everything is expressed through the common
# ExtractionResult interface so the planner can mix strategies freely.
class HttpExtractor < Extractor
  STRATEGY = "http"

  # Status codes the strategy must reason about:
  #   200            -> parse + return results (or captcha/parse failure)
  #   401/403        -> blocked
  #   429            -> rate_limited
  #   408/timeout    -> timed out (retryable)
  #   5xx            -> transient, server-side (retryable)
  def extract(query:, engine:, context: {})
    provider = EngineRegistry.provider_for(engine)
    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    url = provider.endpoint(query: query, context: context)

    response = HttpFetcher.new.get(url, timeout_seconds: timeout_seconds)
    latency = elapsed_ms(started)

    interpret(response, provider: provider, latency: latency)
  rescue Net::OpenTimeout, Net::ReadTimeout, Timeout::Error, Errno::ETIMEDOUT
    failure_result(
      strategy: STRATEGY,
      error_type: "timeout",
      error_message: "Request to #{engine} timed out after #{timeout_seconds}s",
      latency_ms: elapsed_ms(started)
    )
  rescue SocketError, Errno::ECONNREFUSED, Errno::ECONNRESET, EOFError, IOError => e
    failure_result(
      strategy: STRATEGY,
      error_type: "network_error",
      error_message: e.class.name,
      latency_ms: elapsed_ms(started)
    )
  rescue Errors::ExtractionFailed => e
    failure_result(
      strategy: STRATEGY,
      error_type: e.error_type,
      error_message: e.error_message,
      latency_ms: elapsed_ms(started)
    )
  rescue StandardError => e
    failure_result(
      strategy: STRATEGY,
      error_type: "unknown",
      error_message: "#{e.class}: #{e.message}",
      latency_ms: elapsed_ms(started)
    )
  end

  private

  def interpret(response, provider:, latency:)
    case response.status
    when 401
      failure_result(strategy: STRATEGY, error_type: "blocked",
                     error_message: "Engine requires authentication (HTTP 401)", latency_ms: latency, http_status: 401)
    when 403
      failure_result(strategy: STRATEGY, error_type: "blocked",
                     error_message: "Engine refused the request (HTTP 403)", latency_ms: latency, http_status: 403)
    when 408
      failure_result(strategy: STRATEGY, error_type: "timeout",
                     error_message: "Engine request timed out (HTTP 408)", latency_ms: latency, http_status: 408)
    when 429
      failure_result(strategy: STRATEGY, error_type: "rate_limited",
                     error_message: "Engine rate limited the request (HTTP 429)", latency_ms: latency, http_status: 429)
    when 500..599
      failure_result(strategy: STRATEGY, error_type: "unknown",
                     error_message: "Engine returned an internal error (HTTP #{response.status})",
                     latency_ms: latency, http_status: response.status)
    else
      interpret_ok(response.body, provider: provider, latency: latency, status: response.status)
    end
  end

  def interpret_ok(body, provider:, latency:, status:)
    return failure_result(strategy: STRATEGY, error_type: "captcha",
                          error_message: "Engine presented a CAPTCHA challenge",
                          latency_ms: latency, http_status: status) if SerpParser.captcha?(body)

    results = ResultNormalizer.normalize_results(provider.parse(body))

    if results.empty?
      failure_result(strategy: STRATEGY, error_type: "parse_error",
                     error_message: "No organic results found in engine response",
                     latency_ms: latency, http_status: status)
    else
      success_result(strategy: STRATEGY, results: results, latency_ms: latency,
                     http_status: status, metadata: { result_count: results.size, provider: provider.name })
    end
  end

  def timeout_seconds
    Rails.application.config.x.request_timeout_seconds
  end
end
