# Per (engine, strategy) historical statistics aggregated from real extraction
# attempts. The planner feeds these into its strategy score:
#
#   score = success_rate / average_latency_ms
#
# Cheap to compute (indexed by engine) and self-healing: every extraction --
# success or failure -- updates the underlying Attempts collection.
class EngineStrategyStats
  Stat = Struct.new(:strategy, :attempts, :successes, :success_rate, :avg_latency_ms, keyword_init: true) do
    def score
      latency = avg_latency_ms.to_f
      latency = 1.0 if latency <= 0
      success_rate.to_f / latency
    end
  end

  MIN_SAMPLES = 3

  # Returns { strategy => Stat } for one engine, e.g.
  #   { "http" => <...>, "browser" => <...> }
  def self.for_engine(engine)
    rows = ExtractionAttempt.collection.aggregate([
      { "$match" => { engine: engine } },
      {
        "$group" => {
          _id: "$strategy",
          attempts: { "$sum" => 1 },
          successes: { "$sum" => { "$cond" => [ { "$eq" => [ "$status", "success" ] }, 1, 0 ] } },
          avg_latency_ms: { "$avg" => "$latency_ms" }
        }
      }
    ]).to_a

    rows.each_with_object({}) do |row, stats|
      strategy = row["_id"]
      attempts = row["attempts"].to_i
      successes = row["successes"].to_i
      rate = attempts.zero? ? 0.0 : successes.fdiv(attempts)

      stats[strategy] = Stat.new(
        strategy: strategy,
        attempts: attempts,
        successes: successes,
        success_rate: rate,
        avg_latency_ms: row["avg_latency_ms"].to_f
      )
    end
  end
end
