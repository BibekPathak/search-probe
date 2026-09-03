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
    it "persists a failed search and attempt when HTTP is blocked and the browser succeeds (403 -> fallback)" do
      stub_simulated_failure(status: 403)
      stub_browser_worker

      expect { get "/api/v1/search", params: { q: "rust", engine: "google", simulate: "403" } }
        .to change(Search, :count).by(1)
        .and change(ExtractionAttempt, :count).by(2)
        .and change(SearchResult, :count).by(2)

      expect(response).to have_http_status(:ok)
      body = response.parsed_body
      expect(body["metadata"]["strategy"]).to eq("browser")
      expect(body["metadata"]["attempts"]).to eq(2)

      search = Search.first
      expect(search.status).to eq("completed")
      expect(search.strategy).to eq("browser")
      attempts = search.extraction_attempts.order_by(created_at: :asc)
      expect(attempts.map(&:strategy)).to eq(%w[http browser])
      expect(attempts.first.error_type).to eq("blocked")
      expect(attempts.last.status).to eq("success")
    end

    it "falls back to the browser after HTTP rate limiting (429 -> browser)" do
      stub_simulated_failure(status: 429)
      stub_browser_worker

      get "/api/v1/search", params: { q: "rust", engine: "google", simulate: "429" }

      expect(response).to have_http_status(:ok)
      body = response.parsed_body
      expect(body["metadata"]["strategy"]).to eq("browser")
      expect(body["results"]).not_to be_empty
      expect(ExtractionAttempt.first.error_type).to eq("rate_limited")
    end

    it "returns a structured captcha error when HTTP and the browser both hit a CAPTCHA" do
      stub_simulated_engine(body: '<div class="captcha" data-challenge="captcha"></div>')
      stub_browser_worker(success: false, error_type: "captcha", error_message: "challenge")

      get "/api/v1/search", params: { q: "rust", engine: "google", simulate: "captcha" }

      expect(response).to have_http_status(:internal_server_error)
      error = response.parsed_body["error"]
      expect(error["code"]).to eq("extraction_failed")
      expect(error["type"]).to eq("captcha")
      expect(Search.first.status).to eq("failed")
    end

    it "escalates malformed HTML to the browser and reports the final parse error" do
      stub_simulated_engine(body: "<html><body><div class=\"broken\">garbage <<< > <div")
      stub_browser_worker(success: false, error_type: "parse_error", error_message: "no results")

      get "/api/v1/search", params: { q: "rust", engine: "google", simulate: "malformed" }

      expect(response).to have_http_status(:internal_server_error)
      expect(response.parsed_body.dig("error", "type")).to eq("parse_error")
      expect(ExtractionAttempt.count).to eq(2)
    end

    it "retries transient timeouts without escalation and then reports a structured error" do
      stub_simulated_timeout

      get "/api/v1/search", params: { q: "rust", engine: "google" }

      expect(response).to have_http_status(:internal_server_error)
      expect(response.parsed_body.dig("error", "type")).to eq("timeout")
      expect(ExtractionAttempt.count).to eq(3)
      expect(ExtractionAttempt.pluck(:strategy).uniq).to eq(%w[http])
    end

    it "retries server 500s and then reports a structured error" do
      stub_simulated_failure(status: 500, body: "oops")

      get "/api/v1/search", params: { q: "rust", engine: "google", simulate: "500" }

      expect(response).to have_http_status(:internal_server_error)
      expect(response.parsed_body.dig("error", "type")).to eq("unknown")
      expect(ExtractionAttempt.count).to eq(3)
    end
  end
end
