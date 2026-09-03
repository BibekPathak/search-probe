require "rails_helper"

RSpec.describe "Dashboard", type: :request do
  it "renders the operational dashboard server-side" do
    get "/dashboard"

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("SearchProbe")
    expect(response.body).to include('data-stat="total_searches"')
    expect(response.body).to include("Recent extraction attempts")
    expect(response.body).to include("Strategy performance")
  end

  it "includes the client-side refresh script" do
    get "/dashboard"
    expect(response.body).to include('fetch("/api/v1/metrics"')
    expect(response.body).to include('fetch("/api/v1/attempts')
  end
end

RSpec.describe "GET /api/v1/attempts", type: :request do
  it "returns the most recent extraction attempts" do
    stub_simulated_engine(query: "dashboard")
    get "/api/v1/search", params: { q: "dashboard" }, headers: auth_headers
    expect(response).to have_http_status(:ok)

    get "/api/v1/attempts", headers: auth_headers

    expect(response).to have_http_status(:ok)
    body = response.parsed_body
    expect(body["attempts"].size).to eq(1)
    attempt = body["attempts"].first
    expect(attempt["engine"]).to eq("google")
    expect(attempt["strategy"]).to eq("http")
    expect(attempt["status"]).to eq("success")
    expect(attempt["query"]).to eq("dashboard")
    expect(attempt["created_at"]).to be_present
  end

  it "requires authentication" do
    get "/api/v1/attempts"
    expect(response).to have_http_status(:unauthorized)
  end
end
