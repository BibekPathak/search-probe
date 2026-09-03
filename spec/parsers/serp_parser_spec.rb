require "rails_helper"

RSpec.describe SerpParser, type: :parser do
  it "extracts results from builder markup" do
    html = Simulator::SerpBuilder.html(engine: "google", query: "rust", count: 5)

    results = described_class.parse(html)

    expect(results.size).to eq(5)
    first = results.first
    expect(first[:position]).to eq(1)
    expect(first[:title]).to be_present
    expect(first[:url]).to start_with("https://")
    expect(first[:result_type]).to eq("organic")
  end

  it "detects CAPTCHA challenge pages" do
    html = '<div class="captcha" data-challenge="captcha"><h1>Verify you are human</h1></div>'
    expect(described_class.captcha?(html)).to be(true)
    expect(described_class.captcha?("<html><body>normal</body></html>")).to be(false)
  end

  it "returns an empty array for malformed pages without results" do
    expect(described_class.parse("<html><body><div class=\"broken\">garbage <<< >>> </div>")).to be_empty
  end

  it "survives radically malformed markup without raising" do
    expect { described_class.parse("\x00<div unclosed") }.not_to raise_error
  end

  it "reads data-position when present" do
    html = <<~HTML
      <div class="result" data-position="7"><h3 class="result-title"><a href="https://x.example">Seven</a></h3></div>
    HTML

    expect(described_class.parse(html).first[:position]).to eq(7)
  end
end
