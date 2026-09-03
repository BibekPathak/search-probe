module Providers
  # A Provider tells an extractor *where* to fetch a SERP for a given engine and
  # how to turn the bytes into raw result hashes (title/url/snippet/position).
  # SimulatorProvider keeps the deterministic test/demo backend; live providers
  # (Bing RSS / Bing HTML) plug in behind the exact same seam so the API,
  # planner and normalizer never change.
  class Provider
    DEFAULT_COUNT = Simulator::SerpBuilder::DEFAULT_COUNT

    attr_reader :engine

    def initialize(engine)
      @engine = engine
    end

    def live?
      false
    end

    def name
      self.class.name.demodulize.sub(/Provider\z/, "").underscore
    end

    # Absolute URL the extractor (HTTP or browser) should request.
    def endpoint(query:, context: {})
      raise NotImplementedError, "#{self.class} must implement #endpoint"
    end

    # body -> array of raw hashes: { position:, title:, url:, snippet: }
    def parse(body)
      raise NotImplementedError, "#{self.class} must implement #parse"
    end

    protected

    def clean(value)
      value.to_s.gsub(/\s+/, " ").strip
    end
  end
end
