# HTTP extraction strategy.
#
# Cheap and fast: fetch the (simulated) engine page with a plain HTTP client,
# parse the HTML, and normalize. Everything is expressed through the common
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
    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    url = build_url(query: query, engine: engine, simulate: context[:simulate],
                    order: context[:simulate_order])

    response = HttpFetcher.new.get(url, timeout_seconds: timeout_seconds)
    latency = elapsed_ms(started)

    interpret(response, latency: latency)
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

  def build_url(query:, engine:, simulate: nil, order: nil)
    base = Rails.application.config.x.simulator_base_url
    count = Simulator::SerpBuilder::DEFAULT_COUNT
    url = +"#{base}/simulator/#{engine}?q=#{CGI.escape(query)}&count=#{count}"
    url << "&failure=#{CGI.escape(simulate)}" if simulate.present?
    url << "&order=reversed" if order == "reversed"
    url
  end

  def interpret(response, latency:)
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
      interpret_ok(response.body, latency: latency, status: response.status)
    end
  end

  def interpret_ok(body, latency:, status:)
    return failure_result(strategy: STRATEGY, error_type: "captcha",
                          error_message: "Engine presented a CAPTCHA challenge",
                          latency_ms: latency, http_status: status) if SerpParser.captcha?(body)

    results = ResultNormalizer.normalize_results(SerpParser.parse(body))

    if results.empty?
      failure_result(strategy: STRATEGY, error_type: "parse_error",
                     error_message: "No organic results found in engine response",
                     latency_ms: latency, http_status: status)
    else
      success_result(strategy: STRATEGY, results: results, latency_ms: latency,
                     http_status: status, metadata: { result_count: results.size })
    end
  end

  def timeout_seconds
    Rails.application.config.x.request_timeout_seconds
  end
end
