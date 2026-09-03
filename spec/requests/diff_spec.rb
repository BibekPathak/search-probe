require "rails_helper"

RSpec.describe "SERP diff endpoint", type: :request do
  def get_diff(id)
    get "/api/v1/searches/#{id}/diff", headers: auth_headers
  end

  def get_search(params)
    get "/api/v1/search", params: params, headers: auth_headers
  end

  def add_result(search, position, title, url)
    SearchResult.create!(search: search, position: position, title: title, url: url, snippet: "s")
  end

  it "reports no comparison when no previous search exists" do
    search = Search.create!(query: "rust", engine: "google")

    get_diff(search.id)

    expect(response).to have_http_status(:ok)
    body = response.parsed_body
    expect(body["compared_to"]).to be_nil
    expect(body["added"]).to be_empty
  end

  it "reports added/removed/position changes against the previous search" do
    first = Search.create!(query: "rust", engine: "google")
    add_result(first, 1, "Stay", "https://example.com/stay")
    add_result(first, 2, "Leave", "https://example.com/leave")

    second = Search.create!(query: "rust", engine: "google")
    add_result(second, 1, "Fresh", "https://example.com/fresh")
    add_result(second, 2, "Stay", "https://example.com/stay")

    get_diff(second.id)

    expect(response).to have_http_status(:ok)
    body = response.parsed_body
    expect(body["compared_to"]).to eq(first.id.to_s)
    expect(body["added"].map { |r| r["title"] }).to eq([ "Fresh" ])
    expect(body["removed"].map { |r| r["title"] }).to eq([ "Leave" ])
    expect(body["position_changes"]).to include(
      { "title" => "Stay", "url" => "https://example.com/stay", "from" => 1, "to" => 2 }
    )
  end

  it "compares a refreshed search against the previous completed search" do
    stub_simulated_engine(query: "rust web framework")

    get_search(q: "rust web framework", engine: "google")
    expect(response).to have_http_status(:ok)
    first_id = Search.desc(:created_at).first.id

    get_search(q: "rust web framework", engine: "google", force_refresh: "true")
    expect(response).to have_http_status(:ok)
    second_id = Search.desc(:created_at).first.id
    expect(second_id).not_to eq(first_id)

    get_diff(second_id)

    expect(response).to have_http_status(:ok)
    body = response.parsed_body
    expect(body["compared_to"]).to eq(first_id.to_s)
    expect(body["added"]).to be_empty
    expect(body["removed"]).to be_empty
  end

  it "returns 404 for an unknown search" do
    get_diff("000000000000000000000000")
    expect(response).to have_http_status(:not_found)
  end

  describe "end-to-end demo (order reversal)" do
    it "shows position changes when the simulator changes result ordering" do
      stub_ordered_engine(query: "rust web framework", order: "normal")
      stub_ordered_engine(query: "rust web framework", order: "reversed")

      get_search(q: "rust web framework", engine: "google")
      expect(response).to have_http_status(:ok)
      normal_results = response.parsed_body["results"]
      expect(normal_results.map { |r| r["position"] }).to eq((1..8).to_a)

      get_search(q: "rust web framework", engine: "google", simulate_order: "reversed")
      expect(response).to have_http_status(:ok)
      reversed_search = Search.desc(:created_at).first
      expect(reversed_search.query).to eq("rust web framework")

      get_diff(reversed_search.id)

      expect(response).to have_http_status(:ok)
      body = response.parsed_body
      expect(body["added"]).to be_empty
      expect(body["removed"]).to be_empty
      expect(body["position_changes"].size).to eq(8)

      first_normal_url = normal_results.first["url"]
      last_reversed_url = reversed_search.search_results.order_by(position: :asc).last.url
      expect(last_reversed_url).to eq(first_normal_url)

      move = body["position_changes"].find { |c| c["url"] == first_normal_url }
      expect(move["from"]).to eq(1)
      expect(move["to"]).to eq(8)
    end
  end
end
