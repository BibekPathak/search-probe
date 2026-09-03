require "rails_helper"

RSpec.describe "Bing providers", type: :extractor do
  def fixture(name)
    File.read(Rails.root.join("spec/fixtures", name))
  end

  describe Providers::BingRssProvider do
    subject(:provider) { described_class.new("bing") }

    it "reports itself as live with a bing endpoint" do
      expect(provider.live?).to be(true)
      expect(provider.endpoint(query: "rust web framework"))
        .to start_with("https://www.bing.com/search?q=rust+web+framework&format=rss")
    end

    it "parses a real Bing RSS response into canonical organic results" do
      results = provider.parse(fixture("bing_rss_results.xml"))

      expect(results.size).to eq(Providers::Provider::DEFAULT_COUNT)
      expect(results.map { |r| r[:position] }).to eq((1..8).to_a)
      expect(results.first).to include(:position, :title, :url, :snippet)

      results.each do |result|
        expect(result[:title]).to be_present
        expect(result[:url]).to match(%r{\Ahttps?://})
      end
    end
  end

  describe Providers::BingHtmlProvider do
    subject(:provider) { described_class.new("bing") }

    it "reports itself as live with a bing endpoint" do
      expect(provider.live?).to be(true)
      expect(provider.endpoint(query: "rust web framework"))
        .to include("https://www.bing.com/search", "q=rust+web+framework")
    end

    it "parses a real Bing HTML response, unwrapping ck/a redirects" do
      results = provider.parse(fixture("bing_html_results.html"))

      expect(results.size).to eq(Providers::Provider::DEFAULT_COUNT)
      expect(results.first).to include(:position, :title, :url, :snippet)

      results.each do |result|
        expect(result[:title]).to be_present
        expect(result[:url]).to match(%r{\Ahttps?://})
        expect(result[:url]).not_to include("bing.com/ck/a")
      end
    end

    it "handles markup drift gracefully" do
      expect(provider.parse("<html><body><ul><li>nothing here</li></ul></body></html>")).to be_empty
    end
  end
end
