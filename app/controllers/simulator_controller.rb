# Local simulated search engines used by the extraction stack.
#
# The simulator keeps every failure mode local and deterministic so SearchProbe
# can demonstrate retry/fallback behaviour without scraping real engines:
#
#   GET /simulator/google?q=rust
#   GET /simulator/google?q=rust&failure=429
#   GET /simulator/google?q=rust&failure=captcha
#   GET /simulator/google?q=rust&failure=timeout&delay_seconds=7
#   GET /simulator/google?q=rust&order=reversed
#
# `client=browser` makes bot-check style failures (403/429) disappear, as a
# headless browser would sail past them, which is exactly the story the
# extraction planner demonstrates. CAPTCHA and server-side failures (500,
# timeout, malformed HTML) affect every client.
class SimulatorController < ApplicationController
  BOT_CHECK_FAILURES = %w[403 429].freeze

  def show
    engine = params[:engine].to_s
    return render_plain("unknown engine", 404) unless Search::ENGINES.include?(engine)

    failure = params[:failure].to_s
    browser_client = params[:client] == "browser"

    # Client-side bot checks don't bother a real (headless) browser.
    failure = nil if browser_client && BOT_CHECK_FAILURES.include?(failure)

    case failure
    when "403"
      render_plain("403 Forbidden — this search engine refused the automated request.", 403)
    when "429"
      render_plain("429 Too Many Requests — please slow down and retry later.", 429)
    when "500"
      render_plain("500 Internal Server Error — the search engine backend is unhealthy.", 500)
    when "timeout"
      sleep([ params[:delay_seconds].to_f, 0.0 ].max)
      render_html(Simulator::SerpBuilder.html(engine: engine, query: query, count: count, order: order))
    when "captcha"
      render_html(captcha_html(engine))
    when "malformed"
      render_html(malformed_html)
    else
      render_html(Simulator::SerpBuilder.html(engine: engine, query: query, count: count, order: order))
    end
  end

  private

  def query
    params.fetch(:q, "")
  end

  def count
    params.fetch(:count, Simulator::SerpBuilder::DEFAULT_COUNT)
  end

  def order
    params[:order] == "reversed" ? "reversed" : "normal"
  end

  def render_plain(message, status)
    render html: "<html><body><pre>#{CGI.escapeHTML(message)}</pre></body></html>".html_safe, status: status
  end

  def render_html(body)
    render html: body.html_safe
  end

  def captcha_html(engine)
    <<~HTML
      <!DOCTYPE html>
      <html lang="en">
      <head><meta charset="utf-8"><title>Verify you are human</title></head>
      <body>
        <div class="captcha" data-challenge="captcha">
          <h1>Security check</h1>
          <p>Please verify you are human before continuing to #{CGI.escapeHTML(engine)} search.</p>
        </div>
      </body>
      </html>
    HTML
  end

  def malformed_html
    noise = Array.new(60) { [ "<div", ">>", "&nbsp;", "<span", "\x00", "broken=1", "</garbage" ].sample(random: Random.new(1)) }.join
    "<!DOCTYPE html><html><head><title>Broken response</title></head><body><div class=\"unclosed\">#{noise}"
  end
end
