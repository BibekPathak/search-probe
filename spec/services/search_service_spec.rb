require "rails_helper"

RSpec.describe SearchService, type: :service do
  # Double honouring the planner contract; extraction policy is the
  # ExtractionPlanner's own responsibility and covered by its own specs.
  class FakePlanner
    Result = {
      position: 1,
      title: "Axum",
      url: "https://example.com/axum",
      snippet: "A Rust web framework",
      result_type: "organic"
    }.freeze

    attr_reader :calls, :last_context, :last_search

    def initialize(extraction: nil, attempts: 1)
      @extraction = extraction
      @attempts = attempts
      @calls = []
    end

    def call(query:, engine:, search:, request_id: nil, context: {})
      @calls << { query: query, engine: engine, request_id: request_id }
      @last_context = context
      @last_search = search
      extraction = @extraction || success_extraction
      ExtractionPlanner::Outcome.new(extraction: extraction, attempts: Array.new(@attempts, extraction))
    end

    private

    def success_extraction
      ExtractionResult.success(
        strategy: "http", results: [ Result.merge(position: 1), Result.merge(position: 2, title: "Leptos") ],
        latency_ms: 15, http_status: 200
      )
    end
  end

  def build_service(planner)
    described_class.new(planner: planner)
  end

  describe "successful planning" do
    it "persists search + results and returns the outcome" do
      planner = FakePlanner.new
      service = build_service(planner)

      outcome = service.call(query: "rust web framework", engine: "google", request_id: "req-9")

      expect(outcome.query).to eq("rust web framework")
      expect(outcome.engine).to eq("google")
      expect(outcome.cached).to be(false)
      expect(outcome.strategy).to eq("http")
      expect(outcome.attempts).to eq(1)
      expect(outcome.results.size).to eq(2)

      search = outcome.search
      expect(search).to be_persisted
      expect(search.status).to eq("completed")
      expect(search.strategy).to eq("http")
      expect(search.latency_ms).to be_a(Integer)
      expect(search.cache_hit).to be(false)

      expect(SearchResult.count).to eq(2)
      expect(planner.calls.size).to eq(1)
      expect(planner.calls.first).to include(query: "rust web framework", engine: "google", request_id: "req-9")
      expect(planner.last_search).to eq(search)
    end

    it "defaults the engine to google" do
      planner = FakePlanner.new
      build_service(planner).call(query: "rust")
      expect(planner.calls.first[:engine]).to eq("google")
    end

    it "forwards demo context to the planner" do
      planner = FakePlanner.new
      build_service(planner).call(query: "rust", context: { simulate: "429" })
      expect(planner.last_context).to eq(simulate: "429")
    end
  end

  describe "validation" do
    it "raises ValidationError for a blank query without calling the planner" do
      planner = FakePlanner.new
      service = build_service(planner)

      expect { service.call(query: "  ") }
        .to raise_error(Errors::ValidationError) { |e| expect(e.code).to eq("missing_query") }
      expect(Search.count).to eq(0)
      expect(planner.calls).to be_empty
    end

    it "raises ValidationError for an over-long query" do
      service = build_service(FakePlanner.new)
      expect { service.call(query: "a" * 501) }
        .to raise_error(Errors::ValidationError) { |e| expect(e.code).to eq("query_too_long") }
    end

    it "raises UnsupportedEngine for an unknown engine" do
      service = build_service(FakePlanner.new)
      expect { service.call(query: "rust", engine: "yahoo") }
        .to raise_error(Errors::UnsupportedEngine)
    end
  end

  describe "failed planning" do
    it "persists a failed search and raises ExtractionFailed with the final error" do
      extraction = ExtractionResult.failure(
        strategy: "browser", error_type: "captcha", error_message: "CAPTCHA",
        latency_ms: 500, http_status: 200
      )
      service = build_service(FakePlanner.new(extraction: extraction, attempts: 2))

      expect { service.call(query: "rust", engine: "google") }
        .to raise_error(Errors::ExtractionFailed) do |error|
          expect(error.error_type).to eq("captcha")
        end

      search = Search.first
      expect(search.status).to eq("failed")
      expect(search.error_type).to eq("captcha")
      expect(SearchResult.count).to eq(0)
    end
  end
end
