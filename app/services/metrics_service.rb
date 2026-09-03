# Operational metrics fed to GET /api/v1/metrics and the dashboard. Aggregated
# straight from Mongo so they reflect exactly what really happened.
class MetricsService
  TERMINAL_STATUSES = %w[completed failed].freeze

  def self.call
    new.call
  end

  def call
    total = Search.where(:status.in => TERMINAL_STATUSES).count
    completed = Search.where(status: "completed").count
    failed = Search.where(status: "failed").count
    cache_hits = Search.where(cache_hit: true).count

    {
      total_searches: total,
      successful_searches: completed,
      failed_searches: failed,
      success_rate: ratio(completed, total),
      cache_hit_rate: ratio(cache_hits, total),
      average_latency_ms: average_latency,
      strategies: strategy_stats,
      attempts_by_error_type: failure_breakdown
    }
  end

  private

  def ratio(numerator, denominator)
    return 0.0 if denominator.zero?

    (numerator.to_f / denominator).round(4)
  end

  def average_latency
    search_docs = Search.where(status: "completed").ne(latency_ms: nil).only(:latency_ms).pluck(:latency_ms)
    return 0 if search_docs.empty?

    (search_docs.sum.to_f / search_docs.size).round
  end

  # Per-strategy success/latency from extraction attempts, e.g.
  #   { "http" => { success_rate: 0.94, average_latency_ms: 380, attempts: 120 }, ... }
  def strategy_stats
    rows = attempts_grouped_by_strategy
    rows.each_with_object({}) do |row, stats|
      attempts = row["attempts"].to_i
      successes = row["successes"].to_i
      stats[row["_id"]] = {
        success_rate: ratio(successes, attempts),
        average_latency_ms: row["avg_latency_ms"].to_f.round,
        attempts: attempts
      }
    end
  end

  # Failure attempts by error type, e.g. { "timeout" => 4, "rate_limited" => 2 }.
  def failure_breakdown
    rows = ExtractionAttempt.collection.aggregate([
      { "$match" => { status: "failure", error_type: { "$ne" => nil } } },
      { "$group" => { _id: "$error_type", count: { "$sum" => 1 } } }
    ]).to_a

    rows.each_with_object({}) { |row, breakdown| breakdown[row["_id"]] = row["count"].to_i }
  end

  def attempts_grouped_by_strategy
    ExtractionAttempt.collection.aggregate([
      {
        "$group" => {
          _id: "$strategy",
          attempts: { "$sum" => 1 },
          successes: { "$sum" => { "$cond" => [ { "$eq" => [ "$status", "success" ] }, 1, 0 ] } },
          avg_latency_ms: { "$avg" => "$latency_ms" }
        }
      }
    ]).to_a
  end
end
