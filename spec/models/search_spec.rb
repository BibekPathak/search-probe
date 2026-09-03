require "rails_helper"

RSpec.describe Search, type: :model do
  describe "validations" do
    it "is valid with a query, engine and default status" do
      search = described_class.new(query: "rust web framework", engine: "google")

      expect(search).to be_valid
      expect(search.status).to eq("completed")
      expect(search.cache_hit).to be(false)
    end

    it "requires a query" do
      expect(described_class.new(query: "", engine: "google")).not_to be_valid
      expect(described_class.new(query: "  ", engine: "google")).not_to be_valid
    end

    it "rejects queries longer than 500 characters" do
      search = described_class.new(query: "a" * 501, engine: "google")
      expect(search).not_to be_valid
      expect(search.errors[:query]).to include(/500/)
    end

    it "rejects unsupported engines" do
      expect(described_class.new(query: "rust", engine: "yahoo")).not_to be_valid
      expect(described_class.new(query: "rust", engine: "google")).to be_valid
    end

    it "rejects unknown statuses" do
      search = described_class.new(query: "rust", engine: "google", status: "nope")
      expect(search).not_to be_valid
    end
  end

  describe ".previous_for" do
    it "returns the latest completed search for the same query and engine, excluding self" do
      older = create_search("rust web framework", "google", status: "completed", created_days_ago: 3)
      _other = create_search("rust web framework", "bing", status: "completed", created_days_ago: 2)
      _old_failed = create_search("rust web framework", "google", status: "failed", created_days_ago: 1)
      latest = create_search("rust web framework", "google", status: "completed", created_days_ago: 0)

      expect(Search.previous_for(query: "rust web framework", engine: "google")).to eq(latest)
      expect(Search.previous_for(query: "rust web framework", engine: "google", not_id: latest.id)).to eq(older)
    end

    it "returns nil when no previous search exists" do
      expect(Search.previous_for(query: "rust", engine: "google")).to be_nil
    end
  end

  def create_search(query, engine, status:, created_days_ago:)
    search = Search.create!(query: query, engine: engine, status: status)
    search.update_attribute(:created_at, created_days_ago.days.ago)
    search
  end
end
