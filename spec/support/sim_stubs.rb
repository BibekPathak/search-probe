module SimStubs
  # Stub outbound extraction HTTP calls so request/service specs exercise the
  # full Rails stack (Net::HTTP -> extractor -> parser -> normalizer) without a
  # live server on localhost:3000.
  def stub_simulated_engine(engine: "google", query: "rust", body: nil, status: 200)
    html = body || Simulator::SerpBuilder.html(engine: engine, query: query)
    WebMock.stub_request(:get, %r{\Ahttp://localhost:3000/simulator/#{engine}\b})
           .to_return(status: status, body: html, headers: { "Content-Type" => "text/html; charset=utf-8" })
  end

  def stub_simulated_failure(engine: "google", status: 403, body: "blocked")
    WebMock.stub_request(:get, %r{\Ahttp://localhost:3000/simulator/#{engine}\b})
           .to_return(status: status, body: body, headers: { "Content-Type" => "text/html; charset=utf-8" })
  end

  def stub_simulated_timeout(engine: "google")
    WebMock.stub_request(:get, %r{\Ahttp://localhost:3000/simulator/#{engine}\b}).to_timeout
  end

  def default_worker_results(count = 2)
    Array.new(count) do |index|
      {
        "position" => index + 1,
        "title" => "Browser result #{index + 1}",
        "url" => "https://example.com/browser/#{index + 1}",
        "snippet" => "Rendered and extracted by the headless browser.",
        "result_type" => "organic"
      }
    end
  end

  # Stub the Playwright worker contract the BrowserExtractor calls.
  def stub_browser_worker(success: true, results: nil, error_type: nil, error_message: nil, status: 200)
    body =
      if success
        { success: true, results: results || default_worker_results, latency_ms: 120 }
      else
        { success: false, error: { type: error_type, message: error_message }, latency_ms: 120 }
      end

    WebMock.stub_request(:post, %r{\Ahttp://localhost:8001/extract})
           .to_return(status: status, body: JSON.generate(body),
                      headers: { "Content-Type" => "application/json" })
  end
end

RSpec.configure do |config|
  config.include SimStubs
end
