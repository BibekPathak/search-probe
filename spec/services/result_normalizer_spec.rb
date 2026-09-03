require "rails_helper"

RSpec.describe ResultNormalizer, type: :service do
  describe ".normalize_one" do
    it "passes through well-formed organic results" do
      normalized = described_class.normalize_one(
        { position: 3, title: " Axum ", url: "https://example.com/axum", snippet: "A web framework" }
      )

      expect(normalized).to eq(
        position: 3,
        title: "Axum",
        url: "https://example.com/axum",
        snippet: "A web framework",
        result_type: "organic"
      )
    end

    it "accepts string keys and alternative field names" do
      normalized = described_class.normalize_one(
        { "position" => "2", "title" => "Leptos", "href" => "https://example.com/leptos", "description" => "Fine-grained reactivity" }
      )

      expect(normalized[:url]).to eq("https://example.com/leptos")
      expect(normalized[:snippet]).to eq("Fine-grained reactivity")
      expect(normalized[:position]).to eq(2)
    end

    it "fills in missing titles and snippets" do
      normalized = described_class.normalize_one(
        { url: "https://example.com/x" }
      )

      expect(normalized[:title]).to eq("(untitled)")
      expect(normalized[:snippet]).to eq("")
      expect(normalized[:result_type]).to eq("organic")
    end

    it "coerces junk positions to a fallback" do
      normalized = described_class.normalize_one({ url: "https://example.com/x", position: "abc" }, fallback_position: 4)
      expect(normalized[:position]).to eq(4)
    end

    it "returns nil when no usable URL exists" do
      expect(described_class.normalize_one({ title: "no link" })).to be_nil
      expect(described_class.normalize_one(nil)).to be_nil
      expect(described_class.normalize_one("not a hash")).to be_nil
    end

    it "truncates oversized fields" do
      normalized = described_class.normalize_one({ url: "https://example.com/#{'a' * 1100}", title: "t" * 500 })
      expect(normalized[:title].length).to eq(ResultNormalizer::MAX_TITLE)
      expect(normalized[:url].length).to eq(ResultNormalizer::MAX_URL)
    end
  end

  describe ".normalize_results" do
    it "drops unusable entries and re-numbers nothing it cannot fix" do
      results = [
        { position: 1, title: "Keep", url: "https://a.example" },
        { title: "dropped, no url" },
        { position: 3, title: "Also keep", url: "https://b.example" }
      ]

      normalized = described_class.normalize_results(results)

      expect(normalized.size).to eq(2)
      expect(normalized.map { |r| r[:title] }).to eq([ "Keep", "Also keep" ])
    end
  end
end
