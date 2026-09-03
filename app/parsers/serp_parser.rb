class SerpParser
  # CSS hooks shared between the fake SERP markup (Simulator::SerpBuilder) and
  # the real-engine markup we would add later behind the same parser contract.
  RESULT_SELECTOR = ".result"
  CAPTCHA_SELECTOR = ".captcha[data-challenge='captcha']"

  # Parse a SERP HTML document into an array of raw result hashes:
  #   [{ title:, url:, snippet:, position: }]
  #
  # The method is intentionally forgiving (Nokogiri repairs broken markup);
  # "this looks like an engine page at all" is the caller's job.
  def self.parse(html, engine: nil)
    document = Nokogiri::HTML(html.to_s)
    document.css(RESULT_SELECTOR).filter_map do |node|
      raw_from_node(node)
    end
  end

  # True when the page is a bot-check / CAPTCHA challenge rather than results.
  def self.captcha?(html)
    Nokogiri::HTML(html.to_s).at_css(CAPTCHA_SELECTOR).present?
  end

  def self.raw_from_node(node)
    link = node.at_css(".result-title a")
    title_node = link || node.at_css(".result-title")

    title = clean(title_node&.text)
    url = clean(link&.[]("href")) || clean(node.at_css(".result-url")&.text)
    snippet = clean(node.at_css(".result-snippet")&.text)
    position = node["data-position"]&.to_i

    return nil if title.empty? && url.empty?

    {
      position: position,
      title: title.empty? ? "(untitled)" : title,
      url: url.empty? ? nil : url,
      snippet: snippet,
      result_type: "organic"
    }
  end

  def self.clean(value)
    value.to_s.gsub(/\s+/, " ").strip
  end
end
