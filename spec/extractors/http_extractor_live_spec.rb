require "rails_helper"

RSpec.describe HttpExtractor, type: :extractor do
  subject(:extractor) { described_class.new }

  let(:bing_fixture) { File.read(Rails.root.join("spec/fixtures", "bing_html_results.html")) }

  def enable_live_bing!
    allow(Rails.application.config.x).to receive(:live_engines).and_return(%w[bing])
  end

  def stub_bing(status: 200, body: bing_fixture)
    WebMock.stub_request(:get, %r{\Ahttps://www\.bing\.com/search\?})
           .to_return(status: status, body: body, headers: { "Content-Type" => "text/html; charset=utf-8" })
  end

  describe "live extraction (LIVE_ENGINES=bing)" do
    before { enable_live_bing! }

    it "fetches the real Bing endpoint and returns normalized results" do
      stub_bing

      result = extractor.extract(query: "best rust web framework", engine: "bing")

      expect(result).to be_success
      expect(result.strategy).to eq("http")
      expect(result.metadata[:provider]).to eq("bing_html")
      expect(result.results.size).to eq(8)
      expect(result.results.first[:url]).to match(%r{\Ahttps?://})
      expect(result.results.first[:url]).not_to include("bing.com/ck/a")
    end

    it "never forwards simulator-only demo hooks to a live engine" do
      stub = stub_bing

      extractor.extract(query: "rust", engine: "bing", context: { simulate: "429", simulate_order: "reversed" })

      expect(stub).to have_been_requested.times(1)
      expect(a_request(:get, %r{\Ahttps://www\.bing\.com/search\?})
        .with(query: hash_excluding("failure", "order", "client"))).to have_been_made
    end

    it "maps a live 429 to the rate_limited taxonomy" do
      stub_bing(status: 429, body: "slow down")
      result = extractor.extract(query: "rust", engine: "bing")

      expect(result).to be_failure
      expect(result.error_type).to eq("rate_limited")
      expect(result.http_status).to eq(429)
    end

    it "reports parse_error when a live engine returns unparseable content" do
      stub_bing(status: 200, body: "<html><body>challenge page, no results</body></html>")
      result = extractor.extract(query: "rust", engine: "bing")

      expect(result.error_type).to eq("parse_error")
    end
  end
end
