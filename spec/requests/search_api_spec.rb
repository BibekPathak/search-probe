require "rails_helper"

RSpec.describe "GET /api/v1/search", type: :request do
  it "returns normalized results for a valid query" do
    stub_simulated_engine(query: "rust web framework")
    expect { get "/api/v1/search", params: { q: "rust web framework", engine: "google" } }
      .to change(Search, :count).by(1)
      .and change(SearchResult, :count).by(8)
      .and change(ExtractionAttempt, :count).by(1)

    expect(response).to have_http_status(:ok)
    body = response.parsed_body

    expect(body["query"]).to eq("rust web framework")
    expect(body["engine"]).to eq("google")
    expect(body["results"].size).to eq(8)

    first = body["results"].first
    expect(first.keys).to match_array(%w[position title url snippet result_type])
    expect(first["position"]).to eq(1)
    expect(first["title"]).to be_present
    expect(first["url"]).to start_with("https://")
    expect(first["result_type"]).to eq("organic")

    expect(body["metadata"]["cached"]).to be(false)
    expect(body["metadata"]["strategy"]).to eq("http")
    expect(body["metadata"]["attempts"]).to eq(1)
    expect(body["metadata"]["latency_ms"]).to be_a(Integer)

    search = Search.first
    expect(search.status).to eq("completed")
    expect(search.error_type).to be_nil
    expect(search.extraction_attempts.first.status).to eq("success")
  end

  it "defaults the engine to google" do
    stub_simulated_engine(query: "rust")
    get "/api/v1/search", params: { q: "rust" }

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body["engine"]).to eq("google")
  end

  it "returns 400 when q is missing" do
    get "/api/v1/search"

    expect(response).to have_http_status(:bad_request)
    expect(response.parsed_body.dig("error", "code")).to eq("validation_error")
  end

  it "returns 400 when q is blank" do
    get "/api/v1/search", params: { q: "   " }
    expect(response).to have_http_status(:bad_request)
  end

  it "returns 400 when q exceeds 500 characters" do
    get "/api/v1/search", params: { q: "r" * 501 }
    expect(response).to have_http_status(:bad_request)
    expect(response.parsed_body.dig("error", "type")).to eq("query_too_long")
  end

  it "returns 404 for an unsupported engine" do
    get "/api/v1/search", params: { q: "rust", engine: "yahoo" }
    expect(response).to have_http_status(:not_found)
    expect(response.parsed_body.dig("error", "type")).to eq("unsupported_engine")
  end

  describe "failure handling" do
    it "persists a failed search and attempt when the engine blocks HTTP" do
      stub_simulated_failure(status: 403)

      expect { get "/api/v1/search", params: { q: "rust", engine: "google" } }
        .to change(Search, :count).by(1)
        .and change(ExtractionAttempt, :count).by(1)
        .and change(SearchResult, :count).by(0)

      expect(response).to have_http_status(:internal_server_error)
      error = response.parsed_body["error"]
      expect(error["code"]).to eq("extraction_failed")
      expect(error["type"]).to eq("blocked")

      search = Search.first
      expect(search.status).to eq("failed")
      expect(search.error_type).to eq("blocked")
      expect(search.extraction_attempts.first.status).to eq("failure")
    end

    it "reports rate limiting (429)" do
      stub_simulated_failure(status: 429)
      get "/api/v1/search", params: { q: "rust" }
      expect(response.parsed_body.dig("error", "type")).to eq("rate_limited")
      expect(ExtractionAttempt.first.error_type).to eq("rate_limited")
    end

    it "reports CAPTCHA challenges" do
      stub_simulated_engine(body: '<div class="captcha" data-challenge="captcha"></div>')
      get "/api/v1/search", params: { q: "rust" }
      expect(response).to have_http_status(:internal_server_error)
      expect(response.parsed_body.dig("error", "type")).to eq("captcha")
    end

    it "reports timeouts" do
      stub_simulated_timeout
      get "/api/v1/search", params: { q: "rust" }
      expect(response.parsed_body.dig("error", "type")).to eq("timeout")
    end

    it "reports parse errors on malformed HTML" do
      stub_simulated_engine(body: "<html><body><div class=\"broken\">garbage <<< > <div")
      get "/api/v1/search", params: { q: "rust" }
      expect(response.parsed_body.dig("error", "type")).to eq("parse_error")
    end
  end
end
