require "rails_helper"

RSpec.describe ExtractionPlanner, type: :service do
  # Queued-outcome extractor double: returns the next queued ExtractionResult.
  class QueuedExtractor
    attr_reader :strategy, :calls

    def initialize(strategy, outcomes)
      @strategy = strategy
      @outcomes = outcomes.dup
      @calls = []
    end

    def extract(query:, engine:, context: {})
      @calls << { query: query, engine: engine }
      @outcomes.shift || success
    end

    def success
      ExtractionResult.success(strategy: strategy, results: [], latency_ms: 5, http_status: 200)
    end
  end

  class FakePlannerSilentLogger
    def emit(_event, _payload); end
  end

  let(:silent_logger) { FakePlannerSilentLogger.new }

  def failure(strategy, type, http_status: nil)
    ExtractionResult.failure(strategy: strategy, error_type: type,
                             error_message: type, latency_ms: 4, http_status: http_status)
  end

  def build_planner(http:, browser: nil, max_attempts: nil, stats: {})
    extractors = { "http" => http }
    extractors["browser"] = browser if browser
    stats_service = double("stats_service", for_engine: stats)

    described_class.new(
      extractors: extractors,
      recorder: ExtractionAttemptRecorder.new(logger: silent_logger),
      stats_service: stats_service,
      max_attempts: max_attempts,
      backoff: ->(_count) { 0 }
    )
  end

  def build_search
    Search.create!(query: "rust", engine: "google", status: "running")
  end

  describe "HTTP succeeds -> no browser fallback" do
    it "returns the results immediately with a single attempt" do
      http = QueuedExtractor.new("http", [])
      browser = QueuedExtractor.new("browser", [])
      planner = build_planner(http: http, browser: browser)
      search = build_search

      outcome = planner.call(query: "rust", engine: "google", search: search)

      expect(outcome.extraction).to be_success
      expect(outcome.attempts.length).to eq(1)
      expect(http.calls.length).to eq(1)
      expect(browser.calls).to be_empty
      expect(search.extraction_attempts.count).to eq(1)
      expect(search.extraction_attempts.first.strategy).to eq("http")
      expect(search.extraction_attempts.first.status).to eq("success")
    end
  end

  describe "HTTP 429 (rate_limited) -> fallback to browser" do
    it "escalates to the browser, which succeeds" do
      http = QueuedExtractor.new("http", [ failure("http", "rate_limited", http_status: 429) ])
      browser = QueuedExtractor.new("browser", [])
      planner = build_planner(http: http, browser: browser)
      search = build_search

      outcome = planner.call(query: "rust", engine: "google", search: search)

      expect(outcome.extraction).to be_success
      expect(outcome.extraction.strategy).to eq("browser")
      expect(outcome.attempts.map(&:strategy)).to eq(%w[http browser])
      expect(outcome.attempts.map { |a| a.error_type }).to eq([ "rate_limited", nil ])
      expect(search.extraction_attempts.count).to eq(2)
      expect(search.extraction_attempts.map(&:error_type)).to eq([ "rate_limited", nil ])
    end
  end

  describe "HTTP CAPTCHA -> escalate to browser" do
    it "returns a structured captcha failure when the browser also hits the challenge" do
      http = QueuedExtractor.new("http", [ failure("http", "captcha") ])
      browser = QueuedExtractor.new("browser", [ failure("browser", "captcha") ])
      planner = build_planner(http: http, browser: browser)
      search = build_search

      outcome = planner.call(query: "rust", engine: "google", search: search)

      expect(outcome.extraction).to be_failure
      expect(outcome.extraction.error_type).to eq("captcha")
      expect(outcome.attempts.length).to eq(2)
      expect(search.status).to eq("running") # service marks it failed afterwards
    end
  end

  describe "HTTP parse error -> fallback to browser" do
    it "recovers when the rendered page parses cleanly" do
      http = QueuedExtractor.new("http", [ failure("http", "parse_error") ])
      browser = QueuedExtractor.new("browser", [])
      planner = build_planner(http: http, browser: browser)
      search = build_search

      outcome = planner.call(query: "rust", engine: "google", search: search)

      expect(outcome.extraction).to be_success
      expect(outcome.extraction.strategy).to eq("browser")
    end
  end

  describe "transient HTTP failures -> retry with backoff" do
    it "retries HTTP on timeouts without touching the browser" do
      http = QueuedExtractor.new("http", 3.times.map { failure("http", "timeout") })
      browser = QueuedExtractor.new("browser", [])
      planner = build_planner(http: http, browser: browser, max_attempts: 3)
      search = build_search

      outcome = planner.call(query: "rust", engine: "google", search: search)

      expect(outcome.extraction).to be_failure
      expect(outcome.extraction.error_type).to eq("timeout")
      expect(outcome.attempts.length).to eq(3)
      expect(http.calls.length).to eq(3)
      expect(browser.calls).to be_empty
    end

    it "retries HTTP on server 5xx responses" do
      http = QueuedExtractor.new("http", [ failure("http", "unknown", http_status: 500),
                                          failure("http", "unknown", http_status: 500),
                                          failure("http", "unknown", http_status: 500) ])
      planner = build_planner(http: http, max_attempts: 3)
      search = build_search

      outcome = planner.call(query: "rust", engine: "google", search: search)

      expect(outcome.extraction).to be_failure
      expect(outcome.attempts.length).to eq(3)
      expect(http.calls.length).to eq(3)
    end

    it "does not escalate a 500 to the browser" do
      http = QueuedExtractor.new("http", 3.times.map { failure("http", "unknown", http_status: 500) })
      browser = QueuedExtractor.new("browser", [])
      planner = build_planner(http: http, browser: browser, max_attempts: 3)
      search = build_search

      outcome = planner.call(query: "rust", engine: "google", search: search)

      expect(outcome.extraction).to be_failure
      expect(outcome.attempts.length).to eq(3)
      expect(browser.calls).to be_empty
    end
  end

  describe "blocked HTTP -> escalate to browser" do
    it "uses the browser when HTTP is blocked with 403" do
      http = QueuedExtractor.new("http", [ failure("http", "blocked", http_status: 403) ])
      browser = QueuedExtractor.new("browser", [])
      planner = build_planner(http: http, browser: browser)
      search = build_search

      outcome = planner.call(query: "rust", engine: "google", search: search)

      expect(outcome.extraction).to be_success
      expect(outcome.extraction.strategy).to eq("browser")
      expect(outcome.attempts.length).to eq(2)
    end
  end

  describe "all attempts fail" do
    it "returns the last structured error" do
      http = QueuedExtractor.new("http", [ failure("http", "blocked") ])
      browser = QueuedExtractor.new("browser", [ failure("browser", "blocked") ])
      planner = build_planner(http: http, browser: browser)
      search = build_search

      outcome = planner.call(query: "rust", engine: "google", search: search)

      expect(outcome.extraction).to be_failure
      expect(outcome.extraction.error_type).to eq("blocked")
      expect(outcome.attempts.length).to eq(2)
      expect(search.extraction_attempts.count).to eq(2)
      expect(search.extraction_attempts.map(&:status)).to eq(%w[failure failure])
    end
  end

  describe "browser is the last resort" do
    it "never escalates further after a browser failure" do
      http = QueuedExtractor.new("http", [ failure("http", "blocked") ])
      browser = QueuedExtractor.new("browser", [ failure("browser", "captcha") ])
      planner = build_planner(http: http, browser: browser)
      search = build_search

      outcome = planner.call(query: "rust", engine: "google", search: search)

      expect(outcome.attempts.length).to eq(2)
      expect(outcome.extraction.error_type).to eq("captcha")
    end
  end

  describe "initial strategy from historical stats" do
    def stat(strategy, rate, latency, attempts)
      EngineStrategyStats::Stat.new(strategy: strategy, attempts: attempts,
                                    successes: (rate * attempts).round,
                                    success_rate: rate, avg_latency_ms: latency)
    end

    it "prefers HTTP when it is cheap and reliable" do
      stats = {
        "http" => stat("http", 0.95, 250, 40),
        "browser" => stat("browser", 0.99, 2500, 40)
      }
      http = QueuedExtractor.new("http", [])
      planner = build_planner(http: http, stats: stats)
      search = build_search

      planner.call(query: "rust", engine: "google", search: search)

      expect(http.calls.length).to eq(1)
    end

    it "leads with the browser when HTTP reliability is poor and it scores higher" do
      # http: 0.30/300ms = 0.001 ; browser: 0.99/1200ms = 0.000825 -> http still wins,
      # so push http success low enough for the score to flip: 0.15/300ms = 0.0005.
      stats = {
        "http" => stat("http", 0.15, 300, 40),
        "browser" => stat("browser", 0.99, 1200, 40)
      }
      http = QueuedExtractor.new("http", [])
      browser = QueuedExtractor.new("browser", [])
      planner = build_planner(http: http, browser: browser, stats: stats)
      search = build_search

      outcome = planner.call(query: "rust", engine: "google", search: search)

      expect(outcome.extraction.strategy).to eq("browser")
      expect(browser.calls.length).to eq(1)
      expect(http.calls).to be_empty
    end

    it "defaults to HTTP with no history" do
      http = QueuedExtractor.new("http", [])
      browser = QueuedExtractor.new("browser", [])
      planner = build_planner(http: http, browser: browser)
      search = build_search

      planner.call(query: "rust", engine: "google", search: search)

      expect(http.calls.length).to eq(1)
      expect(browser.calls).to be_empty
    end
  end

  describe "hard limits" do
    it "respects MAX_ATTEMPTS when an extractor keeps timing out" do
      http = QueuedExtractor.new("http", 10.times.map { failure("http", "timeout") })
      planner = build_planner(http: http, max_attempts: 3)
      search = build_search

      outcome = planner.call(query: "rust", engine: "google", search: search)

      expect(outcome.attempts.length).to eq(3)
      expect(http.calls.length).to eq(3)
      expect(search.extraction_attempts.count).to eq(3)
    end
  end

  describe "extractor safety" do
    it "records unexpected extractor exceptions as a structured failure" do
      http = Object.new
      def http.extract(query:, engine:, context: {})
        raise "boom"
      end
      planner = build_planner(http: http)
      search = build_search

      outcome = planner.call(query: "rust", engine: "google", search: search)

      expect(outcome.extraction).to be_failure
      expect(outcome.extraction.error_type).to eq("unknown")
      expect(outcome.attempts.length).to eq(1)
      expect(search.extraction_attempts.first.error_type).to eq("unknown")
    end
  end
end
