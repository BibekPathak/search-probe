# Server-side render helpers for the dashboard. The inline JavaScript mirrors
# these exactly so a refresh swaps rows without a full page reload.
module DashboardHelper
  include ERB::Util

  def h(value)
    ERB::Util.html_escape(value)
  end

  def format_rate(value)
    "#{(value.to_f * 100).round(1)}%"
  end

  def render_strategy_rows(metrics)
    strategies = metrics[:strategies] || {}
    if strategies.empty?
      return '<tr><td colspan="4" class="muted">No extraction attempts yet.</td></tr>'.html_safe
    end

    strategies.map do |strategy, stats|
      row = +"<tr>"
      row << "<td><span class=\"pill #{h(strategy)}\">#{h(strategy)}</span></td>"
      row << "<td>#{h(stats[:attempts])}</td>"
      row << "<td>#{format_rate(stats[:success_rate])}</td>"
      row << "<td>#{h(stats[:average_latency_ms])} ms</td>"
      row << "</tr>"
      row.html_safe
    end.join("\n").html_safe
  end

  def render_attempt_rows(attempts)
    attempts.map { |attempt| attempt_row(attempt) }.join("\n").html_safe
  end

  def attempt_row(attempt)
    row = +"<tr>"
    row << "<td>#{h(attempt.created_at&.strftime('%H:%M:%S %F'))}</td>"
    row << "<td>#{h(attempt.search&.query)}</td>"
    row << "<td>#{h(attempt.engine)}</td>"
    row << "<td><span class=\"pill #{h(attempt.strategy)}\">#{h(attempt.strategy)}</span></td>"
    row << "<td><span class=\"pill #{attempt.status}\">#{h(attempt.status)}</span></td>"
    row << "<td>#{h(attempt.latency_ms)} ms</td>"
    row << if attempt.error_type
             "<td><span class=\"err\">#{h(attempt.error_type)}</span></td>"
    else
             '<td><span class="muted">-</span></td>'
    end
    row << "</tr>"
    row.html_safe
  end
end
