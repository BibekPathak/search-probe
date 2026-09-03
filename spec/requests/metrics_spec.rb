require "rails_helper"

RSpec.describe "GET /api/v1/metrics", type: :request do
  def build_search!(query:, status:, strategy: nil, cache_hit: false, latency_ms: nil, error_type: nil, engine: "google")
    Search.create!(
      query: query, engine: engine, status: status, strategy: strategy,
      cache_hit: cache_hit, latency_ms: latency_ms, error_type: error_type
    )
  end

  def add_attempt!(search:, strategy:, status:, error_type: nil, latency_ms: nil, engine: "google")
    ExtractionAttempt.create!(
      search: search, engine: engine, strategy: strategy, status: status,
      error_type: error_type, latency_ms: latency_ms,
      http_status: status == "success" ? 200 : nil
    )
  end

  it "aggregates operational metrics from persisted data" do
    ok1 = build_search!(query: "a", status: "completed", strategy: "http", latency_ms: 100)
    ok2 = build_search!(query: "b", status: "completed", strategy: "http", latency_ms: 300)
    build_search!(query: "a", status: "completed", strategy: "cache", cache_hit: true, latency_ms: 5)
    failed = build_search!(query: "c", status: "failed", error_type: "blocked", strategy: "http")
    build_search!(query: "d", status: "queued")

    add_attempt!(search: ok1, strategy: "http", status: "success", latency_ms: 100)
    add_attempt!(search: ok2, strategy: "http", status: "success", latency_ms: 300)
    add_attempt!(search: failed, strategy: "http", status: "failure", error_type: "blocked", latency_ms: 40)

    get "/api/v1/metrics", headers: auth_headers

    expect(response).to have_http_status(:ok)
    body = response.parsed_body

    expect(body["total_searches"]).to eq(4)
    expect(body["successful_searches"]).to eq(3)
    expect(body["failed_searches"]).to eq(1)
    expect(body["success_rate"]).to be_within(0.0001).of(0.75)
    expect(body["cache_hit_rate"]).to be_within(0.0001).of(0.25)
    expect(body["average_latency_ms"]).to eq(135) # (100 + 300 + 5) / 3

    http = body["strategies"]["http"]
    expect(http["success_rate"]).to be_within(0.001).of(0.667)
    expect(http["attempts"]).to eq(3)
    expect(body["attempts_by_error_type"]).to eq("blocked" => 1)
  end

  it "returns zeros when there is no data" do
    get "/api/v1/metrics", headers: auth_headers

    expect(response).to have_http_status(:ok)
    body = response.parsed_body
    expect(body["total_searches"]).to eq(0)
    expect(body["success_rate"]).to eq(0.0)
    expect(body["strategies"]).to eq({})
  end
end
