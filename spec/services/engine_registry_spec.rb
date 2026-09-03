require "rails_helper"

RSpec.describe EngineRegistry, type: :service do
  it "defaults every engine to the simulator" do
    %w[google bing duckduckgo].each do |engine|
      provider = described_class.provider_for(engine, live_engines: [])

      expect(provider).to be_a(Providers::SimulatorProvider)
      expect(provider.live?).to be(false)
    end
  end

  it "keeps non-enabled engines on the simulator even when others are live" do
    provider = described_class.provider_for("google", live_engines: %w[bing])

    expect(provider).to be_a(Providers::SimulatorProvider)
  end

  it "enables the default Bing HTML adapter when bing is live" do
    provider = described_class.provider_for("bing", live_engines: %w[bing])

    expect(provider).to be_a(Providers::BingHtmlProvider)
    expect(provider.live?).to be(true)
  end

  it "supports bing_rss to force the RSS adapter for the bing engine" do
    provider = described_class.provider_for("bing", live_engines: %w[bing_rss])

    expect(provider).to be_a(Providers::BingRssProvider)
    expect(provider.live?).to be(true)
  end

  it "falls back to the simulator for engines with no live options" do
    provider = described_class.provider_for("duckduckgo", live_engines: %w[bing bing_rss])

    expect(provider).to be_a(Providers::SimulatorProvider)
  end
end
