# Cross-strategy normalization: every extractor (HTTP or browser) must produce
# this canonical shape before results reach the database or the API:
#
#   { "position": 1, "title": "...", "url": "...",
#     "snippet": "...", "result_type": "organic" }
#
# Tolerant by design: missing/odd fields are coerced rather than raised so one
# quirky engine page cannot take down a whole request. A page that yields zero
# usable results is reported upstream as a parse failure instead.
class ResultNormalizer
  MAX_TITLE = 300
  MAX_SNIPPET = 600
  MAX_URL = 1000

  def self.normalize_results(raw_results)
    raw_results
      .each_with_index
      .filter_map { |raw, index| normalize_one(raw, fallback_position: index + 1) }
  end

  def self.normalize_one(raw, fallback_position: nil)
    return nil unless raw.is_a?(Hash)

    url = normalize_url(raw[:url] || raw["url"] || raw[:href] || raw["href"])
    return nil if url.nil?

    position = normalize_position(raw[:position] || raw["position"], fallback_position)
    {
      position: position,
      title: normalize_text(raw[:title] || raw["title"], "(untitled)", MAX_TITLE),
      url: url,
      snippet: normalize_text(raw[:snippet] || raw["snippet"] || raw[:description] || raw["description"], "", MAX_SNIPPET),
      result_type: (raw[:result_type] || raw["result_type"] || "organic").to_s
    }
  end

  def self.normalize_text(value, fallback, max_length)
    text = value.to_s.gsub(/\s+/, " ").strip
    text = fallback if text.empty?
    text.truncate(max_length)
  end

  def self.normalize_url(value)
    url = value.to_s.strip
    return nil if url.empty?

    url.truncate(MAX_URL)
  end

  def self.normalize_position(value, fallback)
    integer = value.to_s.to_i
    integer.positive? ? integer : (fallback || 1)
  end
end
