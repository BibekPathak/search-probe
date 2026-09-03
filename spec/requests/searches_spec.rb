require "rails_helper"

RSpec.describe "Async searches", type: :request do
  def post_search(params = {})
    post "/api/v1/searches", params: params, headers: auth_headers
  end

  def get_search(id)
    get "/api/v1/searches/#{id}", headers: auth_headers
  end

  it "creates a queued search and completes it in the background" do
    stub_simulated_engine(query: "async rust")

    expect { post_search(query: "async rust", engine: "google") }
      .to change(Search, :count).by(1)

    expect(response).to have_http_status(:accepted)
    created = response.parsed_body
    expect(created["status"]).to eq("queued")
    expect(created["query"]).to eq("async rust")

    get_search(created["id"])
    expect(response.parsed_body["status"]).to eq("queued")

    perform_enqueued_jobs

    get_search(created["id"])
    body = response.parsed_body
    expect(body["status"]).to eq("completed")
    expect(body["strategy"]).to eq("http")
    expect(body["results"].size).to eq(8)
    expect(body["cache_hit"]).to be(false)
  end

  it "defaults the engine to google" do
    stub_simulated_engine(query: "auto")
    post_search(query: "auto")

    expect(response).to have_http_status(:accepted)
    perform_enqueued_jobs
    get_search(response.parsed_body["id"])

    expect(response.parsed_body["engine"]).to eq("google")
  end

  it "reports a failed background search with its error type" do
    stub_simulated_failure(status: 403)
    stub_browser_worker(success: false, error_type: "blocked", error_message: "403")

    post_search(query: "blocked", engine: "google")
    perform_enqueued_jobs

    get_search(response.parsed_body["id"])
    body = response.parsed_body
    expect(body["status"]).to eq("failed")
    expect(body["error_type"]).to eq("blocked")
    expect(body["results"]).to be_empty
  end

  it "returns 400 for a missing query" do
    post_search({})
    expect(response).to have_http_status(:bad_request)
  end

  it "returns 404 for an unsupported engine" do
    post_search(query: "rust", engine: "yahoo")
    expect(response).to have_http_status(:not_found)
  end

  it "returns 404 for an unknown search id" do
    get_search("000000000000000000000000")
    expect(response).to have_http_status(:not_found)
  end
end
