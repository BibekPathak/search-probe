require "rails_helper"

RSpec.describe SearchService, type: :service do
  FakeSilentLogger = Class.new do
    def emit(_event, _payload); end
  end

  # Test double honouring the extractor contract without any network access.
  class FakeExtractor
    RESULT_HASH = {
      position: 1,
      title: "Axum",
      url: "https://example.com/axum",
      snippet: "A Rust web framework",
      result_type: "organic"
    }.freeze

    attr_reader :calls

    def initialize(outcome: :success)
      @outcome = outcome
      @calls = []
    end

    def extract(query:, engine:, context: {})
      @calls << { query: query, engine: engine }
      case @outcome
      when :success
        ExtractionResult.success(
          strategy: "http", results: [ RESULT_HASH.merge(position: 1), RESULT_HASH.merge(position: 2, title: "Leptos") ],
          latency_ms: 15, http_status: 200
        )
      when :rate_limited
        ExtractionResult.failure(
          strategy: "http", error_type: "rate_limited", error_message: "429",
          latency_ms: 8, http_status: 429
        )
      end
    end
  end

  def build_service(extractor)
    described_class.new(extractor: extractor, recorder: ExtractionAttemptRecorder.new(logger: FakeSilentLogger.new))
  end

  describe "successful extraction" do
    it "persists search + results + a success attempt and returns the outcome" do
      extractor = FakeExtractor.new(outcome: :success)
      service = build_service(extractor)

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
      expect(search.extraction_attempts.count).to eq(1)
      expect(search.extraction_attempts.first.status).to eq("success")
      expect(extractor.calls.size).to eq(1)
      expect(extractor.calls.first).to eq(query: "rust web framework", engine: "google")
    end

    it "defaults the engine to google" do
      extractor = FakeExtractor.new
      service = build_service(extractor)

      service.call(query: "rust")

      expect(extractor.calls.first[:engine]).to eq("google")
    end
  end

  describe "validation" do
    it "raises ValidationError for a blank query without calling the extractor" do
      extractor = FakeExtractor.new
      service = build_service(extractor)

      expect { service.call(query: "  ") }
        .to raise_error(Errors::ValidationError) { |e| expect(e.code).to eq("missing_query") }
      expect(Search.count).to eq(0)
      expect(extractor.calls).to be_empty
    end

    it "raises ValidationError for an over-long query" do
      service = build_service(FakeExtractor.new)
      expect { service.call(query: "a" * 501) }
        .to raise_error(Errors::ValidationError) { |e| expect(e.code).to eq("query_too_long") }
    end

    it "raises UnsupportedEngine for an unknown engine" do
      service = build_service(FakeExtractor.new)
      expect { service.call(query: "rust", engine: "yahoo") }
        .to raise_error(Errors::UnsupportedEngine)
    end
  end

  describe "failed extraction" do
    it "persists a failed search + failure attempt and raises ExtractionFailed" do
      service = build_service(FakeExtractor.new(outcome: :rate_limited))

      expect { service.call(query: "rust", engine: "google") }
        .to raise_error(Errors::ExtractionFailed) do |error|
          expect(error.error_type).to eq("rate_limited")
          expect(error.http_status).to eq(429)
        end

      search = Search.first
      expect(search.status).to eq("failed")
      expect(search.error_type).to eq("rate_limited")
      expect(search.extraction_attempts.count).to eq(1)
      expect(search.extraction_attempts.first.status).to eq("failure")
      expect(SearchResult.count).to eq(0)
    end
  end
end
