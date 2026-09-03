require "rails_helper"

RSpec.describe HttpExtractor, type: :extractor do
  subject(:extractor) { described_class.new }

  it "returns a successful extraction with normalized results" do
    stub_simulated_engine(query: "rust web framework")

    result = extractor.extract(query: "rust web framework", engine: "google")

    expect(result).to be_success
    expect(result.strategy).to eq("http")
    expect(result.http_status).to eq(200)
    expect(result.latency_ms).to be_a(Integer)
    expect(result.metadata[:result_count]).to eq(8)
    expect(result.results.size).to eq(8)
    expect(result.results.first).to include(:position, :title, :url, :snippet, :result_type)
  end

  it "escapes the query into the URL" do
    request_stub = stub_simulated_engine(query: "ruby on rails")
    extractor.extract(query: "ruby on rails", engine: "google")

    expect(request_stub).to have_been_requested.times(1)
    expect(a_request(:get, %r{\Ahttp://localhost:3000/simulator/google\?})
      .with(query: hash_including("q" => "ruby on rails"))).to have_been_made
  end

  describe "failure mapping" do
    it "maps 403 to blocked" do
      stub_simulated_failure(status: 403)
      result = extractor.extract(query: "rust", engine: "google")

      expect(result).to be_failure
      expect(result.error_type).to eq("blocked")
      expect(result.http_status).to eq(403)
    end

    it "maps 429 to rate_limited" do
      stub_simulated_failure(status: 429)
      result = extractor.extract(query: "rust", engine: "google")
      expect(result.error_type).to eq("rate_limited")
    end

    it "maps 500 to an unknown server error" do
      stub_simulated_failure(status: 500, body: "oops")
      result = extractor.extract(query: "rust", engine: "google")
      expect(result).to be_failure
      expect(result.error_type).to eq("unknown")
      expect(result.http_status).to eq(500)
    end

    it "maps a read timeout to timeout" do
      stub_simulated_timeout
      result = extractor.extract(query: "rust", engine: "google")
      expect(result).to be_failure
      expect(result.error_type).to eq("timeout")
    end

    it "detects CAPTCHA markers on 200 responses" do
      stub_simulated_engine(body: '<div class="captcha" data-challenge="captcha"></div>')
      result = extractor.extract(query: "rust", engine: "google")
      expect(result.error_type).to eq("captcha")
    end

    it "maps unparseable HTML to parse_error" do
      stub_simulated_engine(body: "<html><body><div class=\"broken\">no results at all <<< >>>")
      result = extractor.extract(query: "rust", engine: "google")
      expect(result.error_type).to eq("parse_error")
    end

    it "maps connection errors to network_error" do
      stub_request(:get, /simulator/).to_raise(Errno::ECONNREFUSED)
      result = extractor.extract(query: "rust", engine: "google")
      expect(result.error_type).to eq("network_error")
    end
  end
end
