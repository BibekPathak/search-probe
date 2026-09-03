module Providers
  # Real provider: Bing's public RSS feed (https://www.bing.com/search?format=rss).
  # XML with <item>s is far more stable than scraping HTML, which makes this the
  # reliable "live proof" adapter. Used only when Bing is explicitly enabled via
  # LIVE_ENGINES.
  class BingRssProvider < Provider
    def live?
      true
    end

    def endpoint(query:, context: {})
      "https://www.bing.com/search?q=#{CGI.escape(query)}&format=rss"
    end

    def parse(body)
      document = Nokogiri::XML(body)
      results = []

      document.xpath("//item").each do |item|
        break if results.length >= DEFAULT_COUNT

        title = clean(item.at_xpath("title")&.text)
        url = clean(item.at_xpath("link")&.text)
        next if title.empty? || url.empty?

        snippet = clean(strip_markup(item.at_xpath("description")&.text))
        results << {
          position: results.length + 1,
          title: title,
          url: url,
          snippet: snippet
        }
      end

      results
    end

    private

    def strip_markup(text)
      Nokogiri::HTML.fragment(text.to_s).text
    end
  end
end
