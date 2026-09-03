require "cgi"
require "base64"

module Providers
  # Real provider: Bing's classic HTML results page. This is "scraping" in the
  # SerpApi sense -- Bing serves every organic link through a bing.com/ck/a
  # redirect wrapper, which this adapter decodes back to the real destination
  # URL. Opt-in only via LIVE_ENGINES.
  class BingHtmlProvider < Provider
    RESULT_SELECTOR = "li.b_algo"
    CAPTION_SELECTOR = ".b_caption p"

    def live?
      true
    end

    def endpoint(query:, context: {})
      "https://www.bing.com/search?q=#{CGI.escape(query)}&count=#{DEFAULT_COUNT}"
    end

    def parse(body)
      document = Nokogiri::HTML(body)
      results = []

      document.css(RESULT_SELECTOR).each do |node|
        break if results.length >= DEFAULT_COUNT

        link = node.at_css("h2 a")
        next if link.nil?

        title = clean(link.text)
        url = redirect_target(link, node)
        next if title.empty? || url.empty?

        snippet_node = node.at_css(CAPTION_SELECTOR)
        results << {
          position: results.length + 1,
          title: title,
          url: url,
          snippet: clean(snippet_node&.text)
        }
      end

      results
    end

    private

    # Bing wraps organic links as https://www.bing.com/ck/a?..&u=<payload>. The
    # payload is not reliably decodable anymore, but the <cite> element shows
    # the real destination with ' › ' separating path segments, e.g.
    #   https://example.com › docs › guide  ->  https://example.com/docs/guide
    # Prefer a cleanly decoded u payload, then the cite reconstruction, then the
    # raw href as a last resort.
    def redirect_target(link, node)
      href = link["href"].to_s
      return href unless href.start_with?("https://www.bing.com/ck/a")

      decoded = decode_u_payload(href)
      return decoded if decoded

      cite = clean(node.at_css("cite")&.text)
      return cite.gsub(" › ", "/") if cite.match?(%r{\Ahttps?://})

      href
    end

    def decode_u_payload(href)
      encoded = CGI.parse(URI.parse(href).query.to_s)["u"]&.first
      return nil if encoded.nil? || encoded.empty?

      padded = encoded + ("=" * ((4 - (encoded.length % 4)) % 4))
      decoded = Base64.strict_decode64(padded)
      decoded if decoded.match?(%r{\Ahttps?://})
    rescue StandardError
      nil
    end
  end
end
