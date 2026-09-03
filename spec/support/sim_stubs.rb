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
end

RSpec.configure do |config|
  config.include SimStubs
end
