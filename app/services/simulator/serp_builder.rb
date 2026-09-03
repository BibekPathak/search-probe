module Simulator
  # Deterministic fake SERP generator.
  #
  # For the same (engine, query, order) the output is byte-for-byte identical,
  # which makes caching, retries, and the SERP-diff demo reproducible. The
  # whole simulator exists so SearchProbe can demonstrate retry/fallback
  # behaviour without scraping real search engines.
  class SerpBuilder
    ENGINES = Search::ENGINES

    BRANDS = {
      "google" => { brand: "Google", host: "example.com", label: "Google Search" },
      "bing" => { brand: "Bing", host: "contoso.test", label: "Bing" },
      "duckduckgo" => { brand: "DuckDuckGo", host: "duck.example", label: "DuckDuckGo Search" }
    }.freeze

    DEFAULT_COUNT = 8
    MAX_COUNT = 20

    TITLE_TEMPLATES = [
      "%<q>s — the definitive guide",
      "What is %<q>s? A practical overview",
      "%<q>s documentation and reference",
      "Getting started with %<q>s",
      "%<q>s: best practices for teams",
      "Hands-on %<q>s tutorials",
      "Comparing %<q>s with alternatives",
      "%<q>s tips from practitioners",
      "The official %<q>s community",
      "Learn %<q>s in 2026",
      "%<q>s vs. the competition",
      "Understanding %<q>s internals",
      "%<q>s — frequently asked questions",
      "A gentle introduction to %<q>s",
      "%<q>s cookbook: recipes and examples",
      "Architecture notes on %<q>s",
      "%<q>s performance benchmarks",
      "Migrating to %<q>s: lessons learned",
      "%<q>s design rationale explained",
      "%<q>s cheat sheet"
    ].freeze

    SNIPPET_STEMS = [
      "Everything you need to know about %<q>s in one place.",
      "We compare the most important %<q>s concepts with concrete examples.",
      "A practical tour covering the core ideas behind %<q>s.",
      "Community-vetted guidance for teams adopting %<q>s.",
      "The author explains %<q>s through short, runnable examples.",
      "Updated for 2026, this reference keeps %<q>s approachable.",
      "Deep-dive material on %<q>s, including common pitfalls.",
      "Clear explanations and diagrams help you reason about %<q>s."
    ].freeze

    def self.results(engine:, query:, count: DEFAULT_COUNT, order: "normal")
      new(engine: engine, query: query, count: count, order: order).results
    end

    def self.html(engine:, query:, count: DEFAULT_COUNT, order: "normal", client: nil)
      new(engine: engine, query: query, count: count, order: order).html
    end

    def initialize(engine:, query:, count: DEFAULT_COUNT, order: "normal")
      @engine = engine
      @query = query.to_s.strip
      @count = [ [ count.to_i, 1 ].max, MAX_COUNT ].min
      @order = order == "reversed" ? :reversed : :normal
    end

    # Raw, unsanitized result hashes (position/title/url/snippet).
    def results
      @results ||= begin
        titles = sampled_titles
        titles = titles.reverse if @order == :reversed

        titles.each_with_index.map do |title, index|
          {
            position: index + 1,
            title: title,
            url: result_url(title),
            snippet: result_snippet(title)
          }
        end
      end
    end

    def html
      rows = results.map { |r| result_row_html(r) }.join("\n")
      <<~HTML
        <!DOCTYPE html>
        <html lang="en">
        <head>
          <meta charset="utf-8">
          <title>#{escaped_title} - #{brand[:brand]} Search</title>
        </head>
        <body>
          <header class="simulated-serp">
            <h1>#{brand[:brand]}</h1>
            <p class="simulated-serp-note">Simulated results for &quot;#{CGI.escapeHTML(@query)}&quot; (deterministic, engine=#{@engine})</p>
          </header>
          <main id="search-results" data-engine="#{@engine}">
        #{rows}
          </main>
        </body>
        </html>
      HTML
    end

    def brand
      BRANDS.fetch(@engine)
    end

    private

    def escaped_title
      CGI.escapeHTML(@query)
    end

    def rng
      @rng ||= Random.new(Digest::SHA256.hexdigest("#{@engine}|#{@query}").to_i(16) % (2**32))
    end

    def sampled_titles
      pool = TITLE_TEMPLATES.map { |t| format(t, q: @query.titleize) }
      pool.shuffle(random: rng).first(@count)
    end

    def result_url(title)
      host = brand[:host]
      slug = title.downcase.gsub(/[^a-z0-9]+/, "-").gsub(/\A-|-\z/, "")
      "https://www.#{host}/#{slug}"
    end

    def result_snippet(_title)
      template = SNIPPET_STEMS.sample(random: rng)
      format(template, q: @query)
    end

    def result_row_html(result)
      <<~ROW
            <div class="result" data-position="#{result[:position]}">
              <h3 class="result-title"><a href="#{CGI.escapeHTML(result[:url])}">#{CGI.escapeHTML(result[:title])}</a></h3>
              <div class="result-url">#{CGI.escapeHTML(result[:url])}</div>
              <p class="result-snippet">#{CGI.escapeHTML(result[:snippet])}</p>
            </div>
      ROW
    end
  end
end
