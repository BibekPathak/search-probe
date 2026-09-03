require "rails_helper"

RSpec.describe "Extractor contract", type: :extractor do
  # Every concrete strategy that the planner may invoke. New strategies
  # (BrowserExtractor, real-engine adapters) register themselves here and must
  # satisfy the same contract.
  EXTRACTORS = [ HttpExtractor ].freeze

  EXTRACTORS.each do |extractor_class|
    context extractor_class.name do
      subject(:extractor) { extractor_class.new }

      it "declares a machine-readable STRATEGY" do
        expect(extractor_class::STRATEGY).to be_a(String).and be_present
      end

      it "exposes the common #extract signature" do
        expect(extractor).to respond_to(:extract)
      end

      it "returns an ExtractionResult on success" do
        stub_simulated_engine(query: "contract")
        result = extractor.extract(query: "contract", engine: "google")

        expect(result).to be_an(ExtractionResult)
        expect(result.strategy).to eq(extractor_class::STRATEGY)
        expect(result.success?).to be(true)
        expect(result.results).to all(include(:position, :title, :url, :snippet, :result_type))
      end

      it "returns an ExtractionResult on expected failure (never raises)" do
        stub_simulated_failure(status: 429)

        result = extractor.extract(query: "contract", engine: "google")

        expect(result).to be_an(ExtractionResult)
        expect(result.success?).to be(false)
        expect(result.error_type).to eq("rate_limited")
      end
    end
  end
end
