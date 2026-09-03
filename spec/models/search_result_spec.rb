require "rails_helper"

RSpec.describe SearchResult, type: :model do
  it "requires a search, position, title and url" do
    expect(described_class.new(position: 1, title: "T", url: "https://example.com")).not_to be_valid

    search = create_search
    result = described_class.new(search: search, position: 1, title: "T", url: "https://example.com")
    expect(result).to be_valid
    expect(result.result_type).to eq("organic")
  end

  it "rejects non-positive positions" do
    search = create_search
    expect(described_class.new(search: search, position: 0, title: "T", url: "https://x.example")).not_to be_valid
  end

  it "serializes to the canonical API hash" do
    search = create_search
    result = described_class.create!(search: search, position: 2, title: "T", url: "https://example.com", snippet: "S")

    expect(result.to_api_hash).to eq(
      position: 2, title: "T", url: "https://example.com", snippet: "S", result_type: "organic"
    )
  end

  def create_search
    Search.create!(query: "rust", engine: "google")
  end
end
