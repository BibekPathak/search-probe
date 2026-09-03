require "rails_helper"

RSpec.describe BrowserExtractor, type: :extractor do
  subject(:extractor) { described_class.new }

  it "posts to the worker and returns normalized results on success" do
    stub_browser_worker

    result = extractor.extract(query: "rust web framework", engine: "google")

    expect(result).to be_success
    expect(result.strategy).to eq("browser")
    expect(result.results.size).to eq(2)
    expect(result.results.first).to include(:position, :title, :url, :snippet, :result_type)
    expect(result.metadata[:worker]).to be(true)
  end

  it "asks the worker to navigate like a browser (client=browser) to the simulator" do
    stub = stub_browser_worker

    extractor.extract(query: "rust", engine: "google")

    expect(stub).to have_been_requested.times(1)
    request_body = JSON.parse(WebMock::RequestRegistry.instance.requested_signatures.hash.keys.last.body)
    expect(request_body["engine"]).to eq("google")
    expect(request_body["url"]).to include("/simulator/google?q=rust")
    expect(request_body["url"]).to include("client=browser")
  end

  it "forwards a simulated failure to the worker so fallback demos are realistic" do
    stub = stub_browser_worker
    extractor.extract(query: "rust", engine: "google", context: { simulate: "429" })

    request_body = JSON.parse(WebMock::RequestRegistry.instance.requested_signatures.hash.keys.last.body)
    expect(request_body["url"]).to include("failure=429")
  end

  it "maps a worker captcha failure to the shared taxonomy" do
    stub_browser_worker(success: false, error_type: "captcha", error_message: "challenge")
    result = extractor.extract(query: "rust", engine: "google")

    expect(result).to be_failure
    expect(result.error_type).to eq("captcha")
    expect(result.error_message).to eq("challenge")
  end

  it "maps a worker rate_limited failure" do
    stub_browser_worker(success: false, error_type: "rate_limited", error_message: "429")
    result = extractor.extract(query: "rust", engine: "google")
    expect(result.error_type).to eq("rate_limited")
  end

  it "coerces unknown worker error types to unknown" do
    stub_browser_worker(success: false, error_type: "solar_flare", error_message: "x")
    result = extractor.extract(query: "rust", engine: "google")
    expect(result.error_type).to eq("unknown")
  end

  it "treats an empty success payload as a parse error" do
    stub_browser_worker(results: [])
    result = extractor.extract(query: "rust", engine: "google")
    expect(result).to be_failure
    expect(result.error_type).to eq("parse_error")
  end

  it "reports a non-200 worker response as unknown with its http status" do
    stub_browser_worker(status: 500, success: false)
    result = extractor.extract(query: "rust", engine: "google")
    expect(result).to be_failure
    expect(result.error_type).to eq("unknown")
    expect(result.http_status).to eq(500)
  end

  it "maps a worker timeout to the timeout taxonomy" do
    WebMock.stub_request(:post, %r{\Ahttp://localhost:8001/extract}).to_timeout
    result = extractor.extract(query: "rust", engine: "google")
    expect(result.error_type).to eq("timeout")
  end

  it "maps connection errors to network_error" do
    stub_request(:post, %r{\Ahttp://localhost:8001/extract}).to_raise(Errno::ECONNREFUSED)
    result = extractor.extract(query: "rust", engine: "google")
    expect(result.error_type).to eq("network_error")
  end
end
