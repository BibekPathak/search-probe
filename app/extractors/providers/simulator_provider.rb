module Providers
  # The deterministic local simulator. Honors the demo-only context hooks
  # (simulate = failure mode, simulate_order = reversed ranking, client =
  # browser bypass) that a real provider would never see.
  class SimulatorProvider < Provider
    def endpoint(query:, context: {})
      base = Rails.application.config.x.simulator_base_url
      url = +"#{base}/simulator/#{engine}?q=#{CGI.escape(query)}&count=#{DEFAULT_COUNT}"
      url << "&failure=#{CGI.escape(context[:simulate])}" if context[:simulate].present?
      url << "&order=reversed" if context[:simulate_order] == "reversed"
      url << "&client=browser" if context[:client] == "browser"
      url
    end

    def parse(body)
      SerpParser.parse(body)
    end
  end
end
