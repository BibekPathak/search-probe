require "rails_helper"

RSpec.describe "Simulator", type: :request do
  it "serves deterministic SERP HTML for a supported engine" do
    get "/simulator/google", params: { q: "rust web framework" }

    expect(response).to have_http_status(:ok)
    expect(response.media_type).to eq("text/html")

    first = response.body.scan(/<h3 class="result-title">.*?<\/h3>/).first
    expect(first).to include("Rust Web Framework")
    expect(response.body).to include('data-engine="google"')
    expect(response.body.scan('<div class="result"').size).to eq(8)
  end

  it "is deterministic for the same engine + query" do
    get "/simulator/google", params: { q: "determinism" }
    first_body = response.body

    get "/simulator/google", params: { q: "determinism" }
    expect(response.body).to eq(first_body)
  end

  it "varies markup by engine" do
    get "/simulator/google", params: { q: "rust" }
    expect(response.body).to include("Google")

    get "/simulator/duckduckgo", params: { q: "rust" }
    expect(response.body).to include("DuckDuckGo")
  end

  it "reverses ordering with order=reversed" do
    get "/simulator/google", params: { q: "rust", order: "reversed" }
    reversed_first = response.body.scan(/<h3 class="result-title"><a href="([^"]+)"/).flatten.first

    get "/simulator/google", params: { q: "rust" }
    normal_first = response.body.scan(/<h3 class="result-title"><a href="([^"]+)"/).flatten.first

    expect(reversed_first).not_to eq(normal_first)
    expect(response.body.scan(/<h3 class="result-title">/).size).to eq(8)
  end

  describe "failure modes" do
    it "returns 403 for failure=403" do
      get "/simulator/google", params: { q: "rust", failure: "403" }
      expect(response).to have_http_status(:forbidden)
      expect(response.body).to match(/403 Forbidden/i)
    end

    it "returns 429 for failure=429" do
      get "/simulator/google", params: { q: "rust", failure: "429" }
      expect(response).to have_http_status(:too_many_requests)
      expect(response.body).to match(/429 Too Many Requests/i)
    end

    it "returns 500 for failure=500" do
      get "/simulator/google", params: { q: "rust", failure: "500" }
      expect(response).to have_http_status(:internal_server_error)
    end

    it "returns a CAPTCHA marker page for failure=captcha" do
      get "/simulator/google", params: { q: "rust", failure: "captcha" }
      expect(response).to have_http_status(:ok)
      expect(response.body).to include('data-challenge="captcha"')
    end

    it "returns malformed HTML for failure=malformed" do
      get "/simulator/google", params: { q: "rust", failure: "malformed" }
      expect(response).to have_http_status(:ok)
      expect(response.body).not_to include('<div class="result"')
    end

    it "delays a response for failure=timeout" do
      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      get "/simulator/google", params: { q: "rust", failure: "timeout", delay_seconds: 0.2 }
      elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started

      expect(response).to have_http_status(:ok)
      expect(elapsed).to be >= 0.15
    end
  end

  describe "browser client bypass" do
    it "lets a browser client through bot-check failures" do
      get "/simulator/google", params: { q: "rust", failure: "429", client: "browser" }
      expect(response).to have_http_status(:ok)
      expect(response.body).to include('<div class="result"')
    end

    it "still shows CAPTCHA to a browser client" do
      get "/simulator/google", params: { q: "rust", failure: "captcha", client: "browser" }
      expect(response).to have_http_status(:ok)
      expect(response.body).to include('data-challenge="captcha"')
    end
  end

  it "404s unknown engines at the route level" do
    get "/simulator/yahoo", params: { q: "rust" }
    expect(response).to have_http_status(:not_found)
  end
end
