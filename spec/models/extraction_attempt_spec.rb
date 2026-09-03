require "rails_helper"

RSpec.describe ExtractionAttempt, type: :model do
  it "records a successful attempt" do
    attempt = described_class.create!(
      search: Search.create!(query: "rust", engine: "google"),
      engine: "google", strategy: "http", status: "success", http_status: 200, latency_ms: 42
    )

    expect(attempt).to be_persisted
    expect(attempt.error_type).to be_nil
    expect(attempt.created_at).to be_present
  end

  it "records a failed attempt with the canonical error taxonomy" do
    attempt = described_class.create!(
      search: Search.create!(query: "rust", engine: "google"),
      engine: "google", strategy: "http", status: "failure", http_status: 429,
      latency_ms: 10, error_type: "rate_limited", error_message: "too many requests"
    )

    expect(attempt).to be_persisted
    expect(ExtractionAttempt::ERROR_TYPES).to include(attempt.error_type)
  end

  it "rejects unknown error types" do
    search = Search.create!(query: "rust", engine: "google")
    attempt = described_class.new(
      search: search, engine: "google", strategy: "http",
      status: "failure", error_type: "crystal_meth"
    )

    expect(attempt).not_to be_valid
    expect(attempt.errors[:error_type]).to be_present
  end

  it "rejects unknown strategies" do
    search = Search.create!(query: "rust", engine: "google")
    attempt = described_class.new(
      search: search, engine: "google", strategy: "telepathy", status: "success"
    )

    expect(attempt).not_to be_valid
  end
end
