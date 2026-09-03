require "rails_helper"

RSpec.describe ExtractionAttemptRecorder, type: :service do
  FakeRecorderLogger = Class.new do
    attr_reader :events

    def initialize
      @events = []
    end

    def emit(event, payload)
      @events << { event: event, payload: payload }
    end
  end

  let(:logger) { FakeRecorderLogger.new }
  subject(:recorder) { described_class.new(logger: logger) }

  def build_search
    Search.create!(query: "rust", engine: "google")
  end

  it "persists a success attempt and emits an extraction_attempt event" do
    search = build_search
    extraction = ExtractionResult.success(
      strategy: "http", results: [], latency_ms: 40, http_status: 200
    )

    attempt = recorder.call(search: search, engine: "google", extraction: extraction, request_id: "req-123")

    expect(attempt).to be_persisted
    expect(attempt.status).to eq("success")
    expect(attempt.http_status).to eq(200)
    expect(attempt.latency_ms).to eq(40)
    expect(attempt.error_type).to be_nil

    event = logger.events.first
    expect(event[:event]).to eq("extraction_attempt")
    expect(event[:payload]).to include(
      request_id: "req-123",
      search_id: search.id.to_s,
      engine: "google",
      strategy: "http",
      success: true
    )
    expect(event[:payload]).not_to have_key(:error_type)
  end

  it "persists a failure attempt with error metadata" do
    search = build_search
    extraction = ExtractionResult.failure(
      strategy: "http", error_type: "rate_limited", error_message: "slow down",
      latency_ms: 12, http_status: 429
    )

    attempt = recorder.call(search: search, engine: "google", extraction: extraction)

    expect(attempt.status).to eq("failure")
    expect(attempt.error_type).to eq("rate_limited")
    expect(attempt.error_message).to eq("slow down")
    expect(attempt.http_status).to eq(429)

    event = logger.events.first
    expect(event[:payload]).to include(success: false, error_type: "rate_limited", http_status: 429)
  end

  it "links the attempt to the search" do
    search = build_search
    extraction = ExtractionResult.success(strategy: "browser", results: [], latency_ms: 1, http_status: 200)

    attempt = recorder.call(search: search, engine: "google", extraction: extraction)

    expect(search.extraction_attempts).to contain_exactly(attempt)
  end
end
