require "rails_helper"

RSpec.describe "GET /api/v1/search", type: :request do
  def search(params = {}, headers = nil)
    get "/api/v1/search", params: params, headers: headers || auth_headers
  end

  it "returns normalized results for a valid query" do
    stub_simulated_engine(query: "rust web framework")

    expect { search(q: "rust web framework", engine: "google") }
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

    search_doc = Search.first
    expect(search_doc.status).to eq("completed")
    expect(search_doc.error_type).to be_nil
    expect(search_doc.extraction_attempts.first.status).to eq("success")
  end

  it "defaults the engine to google" do
    stub_simulated_engine(query: "rust")
    search(q: "rust")

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body["engine"]).to eq("google")
  end

  it "returns 400 when q is missing" do
    search({})
    expect(response).to have_http_status(:bad_request)
    expect(response.parsed_body.dig("error", "code")).to eq("validation_error")
  end

  it "returns 400 when q is blank" do
    search(q: "   ")
    expect(response).to have_http_status(:bad_request)
  end

  it "returns 400 when q exceeds 500 characters" do
    search(q: "r" * 501)
    expect(response).to have_http_status(:bad_request)
    expect(response.parsed_body.dig("error", "type")).to eq("query_too_long")
  end

  it "returns 404 for an unsupported engine" do
    search(q: "rust", engine: "yahoo")
    expect(response).to have_http_status(:not_found)
    expect(response.parsed_body.dig("error", "type")).to eq("unsupported_engine")
  end

  describe "authentication" do
    it "returns 401 without an API key" do
      stub_simulated_engine
      get "/api/v1/search", params: { q: "rust" }
      expect(response).to have_http_status(:unauthorized)
      expect(Search.count).to eq(0)
    end

    it "returns 401 for an invalid API key" do
      get "/api/v1/search", params: { q: "rust" }, headers: { "X-API-Key" => "nope" }
      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe "caching" do
    it "serves the second identical request from cache" do
      stub_simulated_engine(query: "cache me")

      search(q: "cache me", engine: "google")
      first_results = response.parsed_body["results"]

      expect { search(q: "cache me", engine: "google") }.to change(ExtractionAttempt, :count).by(0)

      expect(response).to have_http_status(:ok)
      body = response.parsed_body
      expect(body["results"]).to eq(first_results)
      expect(body["results"].size).to eq(8)
      expect(body["metadata"]["cached"]).to be(true)
      expect(body["metadata"]["strategy"]).to eq("cache")
      expect(body["metadata"]["attempts"]).to eq(0)

      second_search = Search.desc(:created_at).first
      expect(second_search.cache_hit).to be(true)
      expect(second_search.strategy).to eq("cache")
    end

    it "is case/whitespace insensitive to the query" do
      stub_simulated_engine(query: "Cache Me")

      search(q: "Cache Me", engine: "google")
      expect(response.parsed_body["metadata"]["cached"]).to be(false)

      search(q: "  cache me  ", engine: "google")
      expect(response.parsed_body["metadata"]["cached"]).to be(true)
    end

    it "bypasses the cache with force_refresh=true" do
      stub_simulated_engine(query: "fresh please")

      search(q: "fresh please", engine: "google")
      expect(response.parsed_body["metadata"]["cached"]).to be(false)

      expect { search(q: "fresh please", engine: "google", force_refresh: "true") }
        .to change(ExtractionAttempt, :count).by(1)

      expect(response.parsed_body["metadata"]["cached"]).to be(false)
      expect(Search.count).to eq(2)
    end
  end

  describe "failure handling" do
    it "persists a failed search and attempt when HTTP is blocked and the browser succeeds (403 -> fallback)" do
      stub_simulated_failure(status: 403)
      stub_browser_worker

      expect { search(q: "rust", engine: "google", simulate: "403") }
        .to change(Search, :count).by(1)
        .and change(ExtractionAttempt, :count).by(2)
        .and change(SearchResult, :count).by(2)

      expect(response).to have_http_status(:ok)
      body = response.parsed_body
      expect(body["metadata"]["strategy"]).to eq("browser")
      expect(body["metadata"]["attempts"]).to eq(2)

      search_doc = Search.first
      expect(search_doc.status).to eq("completed")
      expect(search_doc.strategy).to eq("browser")
      attempts = search_doc.extraction_attempts.order_by(created_at: :asc)
      expect(attempts.map(&:strategy)).to eq(%w[http browser])
      expect(attempts.first.error_type).to eq("blocked")
      expect(attempts.last.status).to eq("success")
    end

    it "falls back to the browser after HTTP rate limiting (429 -> browser)" do
      stub_simulated_failure(status: 429)
      stub_browser_worker

      search(q: "rust", engine: "google", simulate: "429")

      expect(response).to have_http_status(:ok)
      body = response.parsed_body
      expect(body["metadata"]["strategy"]).to eq("browser")
      expect(body["results"]).not_to be_empty
      expect(ExtractionAttempt.first.error_type).to eq("rate_limited")
    end

    it "returns a structured captcha error when HTTP and the browser both hit a CAPTCHA" do
      stub_simulated_engine(body: '<div class="captcha" data-challenge="captcha"></div>')
      stub_browser_worker(success: false, error_type: "captcha", error_message: "challenge")

      search(q: "rust", engine: "google", simulate: "captcha")

      expect(response).to have_http_status(:internal_server_error)
      error = response.parsed_body["error"]
      expect(error["code"]).to eq("extraction_failed")
      expect(error["type"]).to eq("captcha")
      expect(Search.first.status).to eq("failed")
    end

    it "escalates malformed HTML to the browser and reports the final parse error" do
      stub_simulated_engine(body: "<html><body><div class=\"broken\">garbage <<< > <div")
      stub_browser_worker(success: false, error_type: "parse_error", error_message: "no results")

      search(q: "rust", engine: "google", simulate: "malformed")

      expect(response).to have_http_status(:internal_server_error)
      expect(response.parsed_body.dig("error", "type")).to eq("parse_error")
      expect(ExtractionAttempt.count).to eq(2)
    end

    it "retries transient timeouts without escalation and then reports a structured error" do
      stub_simulated_timeout

      search(q: "rust", engine: "google")

      expect(response).to have_http_status(:internal_server_error)
      expect(response.parsed_body.dig("error", "type")).to eq("timeout")
      expect(ExtractionAttempt.count).to eq(3)
      expect(ExtractionAttempt.pluck(:strategy).uniq).to eq(%w[http])
    end

    it "retries server 500s and then reports a structured error" do
      stub_simulated_failure(status: 500, body: "oops")

      search(q: "rust", engine: "google", simulate: "500")

      expect(response).to have_http_status(:internal_server_error)
      expect(response.parsed_body.dig("error", "type")).to eq("unknown")
      expect(ExtractionAttempt.count).to eq(3)
    end
  end
end
