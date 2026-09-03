require "rails_helper"

RSpec.describe "API security", type: :request do
  def get_search(params, headers:)
    get "/api/v1/search", params: params, headers: headers
  end

  describe "authentication" do
    it "rejects requests without an API key" do
      stub_simulated_engine
      get "/api/v1/search", params: { q: "rust" }

      expect(response).to have_http_status(:unauthorized)
      expect(response.parsed_body.dig("error", "type")).to eq("invalid_api_key")
    end

    it "rejects unknown API keys" do
      stub_simulated_engine
      get "/api/v1/search", params: { q: "rust" }, headers: { "X-API-Key" => "definitely-not-real" }

      expect(response).to have_http_status(:unauthorized)
    end

    it "never stores the raw key, only a hash" do
      ApiKey.create!(name: "secret-holder", key_digest: ApiKey.hash_token("super-secret"))

      expect(ApiKey.find_by(name: "secret-holder").key_digest).not_to eq("super-secret")
      expect(ApiKey.find_by(name: "secret-holder").key_digest).to start_with("$2")
    end

    it "accepts a valid key" do
      stub_simulated_engine
      get_search({ q: "rust" }, headers: auth_headers)

      expect(response).to have_http_status(:ok)
    end
  end

  describe "rate limiting" do
    it "returns 429 with Retry-After once the per-minute limit is exceeded" do
      stub_simulated_engine(query: "rate")

      allow(Rails.application.config.x).to receive(:rate_limit_per_minute).and_return(3)

      3.times do
        get_search({ q: "rate" }, headers: auth_headers)
        expect(response).to have_http_status(:ok)
      end

      get_search({ q: "rate" }, headers: auth_headers)

      expect(response).to have_http_status(:too_many_requests)
      expect(response.headers["Retry-After"]).to be_present
      error = response.parsed_body["error"]
      expect(error["code"]).to eq("rate_limited")
      expect(RateLimitEntry.count).to eq(1)
    end

    it "tracks limits per API key, not globally" do
      stub_simulated_engine(query: "split")
      allow(Rails.application.config.x).to receive(:rate_limit_per_minute).and_return(1)

      first_key = ApiKey.create!(name: "first", key_digest: ApiKey.hash_token("token-a"))
      second_key = ApiKey.create!(name: "second", key_digest: ApiKey.hash_token("token-b"))

      get_search({ q: "split" }, headers: { "X-API-Key" => "token-a" })
      expect(response).to have_http_status(:ok)

      # token-a is now over its own limit...
      get_search({ q: "split" }, headers: { "X-API-Key" => "token-a" })
      expect(response).to have_http_status(:too_many_requests)

      # ...but token-b still has quota.
      get_search({ q: "split" }, headers: { "X-API-Key" => "token-b" })
      expect(response).to have_http_status(:ok)

      expect(RateLimitEntry.count).to eq(2)
      expect(first_key).to be_present
      expect(second_key).to be_present
    end
  end
end
