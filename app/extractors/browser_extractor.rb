# Playwright browser extraction strategy.
#
# Used as a fallback when plain HTTP extraction is blocked, rate-limited, or
# hits a challenge/parse wall. Rails never runs a browser itself: it asks the
# remote BrowserWorker (a separate Python + Playwright service) to render a
# page and return normalized organic results. Same ExtractionResult contract as
# HttpExtractor, so the planner treats both strategies uniformly.
class BrowserExtractor < Extractor
  STRATEGY = "browser"

  def extract(query:, engine:, context: {})
    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    url = build_url(query: query, engine: engine, simulate: context[:simulate])

    response = WorkerClient.post(worker_base_url, "/extract",
                                 body: { url: url, query: query, engine: engine },
                                 timeout_seconds: timeout_seconds)
    latency = elapsed_ms(started)

    interpret(response, latency: latency)
  rescue Net::OpenTimeout, Net::ReadTimeout, Timeout::Error, Errno::ETIMEDOUT
    failure_result(strategy: STRATEGY, error_type: "timeout",
                   error_message: "Browser worker did not respond within #{timeout_seconds}s",
                   latency_ms: elapsed_ms(started))
  rescue SocketError, Errno::ECONNREFUSED, Errno::ECONNRESET, EOFError, IOError => e
    failure_result(strategy: STRATEGY, error_type: "network_error",
                   error_message: "Browser worker unreachable: #{e.class}",
                   latency_ms: elapsed_ms(started))
  rescue StandardError => e
    failure_result(strategy: STRATEGY, error_type: "unknown",
                   error_message: "#{e.class}: #{e.message}",
                   latency_ms: elapsed_ms(started))
  end

  private

  def interpret(response, latency:)
    return failure_result(strategy: STRATEGY, error_type: "unknown",
                          error_message: "Browser worker returned HTTP #{response.status}",
                          latency_ms: latency, http_status: response.status) unless response.status == 200

    payload = parse_json(response.body)
    return payload_failure(payload, latency) unless payload.dig("success") == true

    results = ResultNormalizer.normalize_results(payload.fetch("results", []))
    if results.empty?
      failure_result(strategy: STRATEGY, error_type: "parse_error",
                     error_message: "Browser worker returned no organic results",
                     latency_ms: latency, http_status: 200)
    else
      success_result(
        strategy: STRATEGY,
        results: results,
        latency_ms: latency,
        http_status: payload.dig("metadata", "http_status") || 200,
        metadata: { result_count: results.size, worker: true }
      )
    end
  end

  def payload_failure(payload, latency)
    error = payload["error"] || {}
    type = error["type"].to_s
    type = "unknown" unless ExtractionAttempt::ERROR_TYPES.include?(type)

    failure_result(strategy: STRATEGY, error_type: type,
                   error_message: error["message"].to_s.presence || "Browser worker reported a failure",
                   latency_ms: latency,
                   http_status: error["http_status"] || payload.dig("metadata", "http_status"))
  end

  def parse_json(body)
    JSON.parse(body)
  rescue JSON::ParserError
    {}
  end

  def build_url(query:, engine:, simulate: nil)
    base = Rails.application.config.x.simulator_base_url
    url = +"#{base}/simulator/#{engine}?q=#{CGI.escape(query)}"
    url << "&client=browser"
    url << "&failure=#{CGI.escape(simulate)}" if simulate.present?
    url
  end

  def worker_base_url
    Rails.application.config.x.browser_worker_url
  end

  def timeout_seconds
    Rails.application.config.x.browser_worker_timeout_seconds
  end
end
