# Resolves an engine to the provider the extractors should use.
#
# The local simulator is always the default -- SearchProbe is deterministic
# unless you explicitly opt engines into live extraction with LIVE_ENGINES
# (e.g. "bing" or "bing,bing_rss"). Live providers sit behind the exact same
# Provider seam, so toggling them never touches the API, planner or models.
class EngineRegistry
  # engine => { live provider keys => provider class }. Ordering matters: the
  # first key is the default live provider for that engine.
  OPTIONS = {
    "bing" => {
      "bing_html" => Providers::BingHtmlProvider,
      "bing_rss" => Providers::BingRssProvider
    }
  }.freeze

  def self.provider_for(engine, live_engines: nil)
    live = live_engines || Rails.application.config.x.live_engines
    options = OPTIONS[engine]

    if options
      active = (live & options.keys).first
      active ||= options.keys.first if live.include?(engine)

      return options.fetch(active).new(engine) if active
    end

    Providers::SimulatorProvider.new(engine)
  end
end
