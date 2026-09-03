require "rails_helper"

RSpec.describe EngineStrategyStats, type: :service do
  def add_attempt(engine:, strategy:, status:, latency_ms:)
    ExtractionAttempt.create!(
      search: Search.create!(query: "rust", engine: engine),
      engine: engine, strategy: strategy, status: status,
      latency_ms: latency_ms, http_status: status == "success" ? 200 : nil
    )
  end

  it "aggregates success rate and average latency per strategy for an engine" do
    add_attempt(engine: "google", strategy: "http", status: "success", latency_ms: 100)
    add_attempt(engine: "google", strategy: "http", status: "success", latency_ms: 200)
    add_attempt(engine: "google", strategy: "http", status: "failure", latency_ms: 50)
    add_attempt(engine: "google", strategy: "browser", status: "success", latency_ms: 1500)
    add_attempt(engine: "bing", strategy: "http", status: "failure", latency_ms: 10)

    stats = described_class.for_engine("google")

    http = stats.fetch("http")
    expect(http.attempts).to eq(3)
    expect(http.successes).to eq(2)
    expect(http.success_rate).to be_within(0.001).of(0.667)
    expect(http.avg_latency_ms).to be_within(0.1).of(116.7)
    expect(http.score).to be > 0

    browser = stats.fetch("browser")
    expect(browser.attempts).to eq(1)
    expect(browser.success_rate).to eq(1.0)

    expect(stats.keys).to contain_exactly("http", "browser")
    expect(stats).not_to have_key("bing")
  end

  it "returns an empty hash for an engine with no history" do
    expect(described_class.for_engine("duckduckgo")).to eq({})
  end

  it "computes a score that rewards reliability and punishes latency" do
    fast = described_class::Stat.new(strategy: "http", attempts: 10, successes: 9,
                                     success_rate: 0.9, avg_latency_ms: 100)
    slow = described_class::Stat.new(strategy: "browser", attempts: 10, successes: 10,
                                     success_rate: 1.0, avg_latency_ms: 2500)

    expect(fast.score).to be > slow.score
  end
end
