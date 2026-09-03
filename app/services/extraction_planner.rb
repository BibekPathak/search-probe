# Adaptive extraction planner.
#
# Owns the extraction policy so SearchService never talks to a concrete
# scraper. Decisions:
#
#   * pick an initial strategy from historical engine+strategy stats
#     (score = success_rate / average_latency_ms; HTTP normally wins because it
#     is cheap, unless its historical reliability is bad);
#   * on a successful attempt -> return immediately;
#   * on a transient failure (timeout / network / server 5xx) -> retry the
#     same strategy with backoff, bounded by MAX_ATTEMPTS;
#   * on a bot-check style failure (blocked / captcha / parse / rate_limited)
#     -> escalate to the browser, which renders like a real browser would;
#   * on a browser failure -> give up with a structured error (nothing left to
#     try -- we never bypass real CAPTCHAs).
#
# Every single attempt is recorded in ExtractionAttempt + logged, whether it
# succeeds or fails, so the stats and metrics stay truthful.
class ExtractionPlanner
  Outcome = Struct.new(:extraction, :attempts, keyword_init: true)

  TRANSIENT_ERRORS = %w[timeout network_error].freeze
  ESCALATE_TO_BROWSER = %w[blocked captcha parse_error rate_limited].freeze

  def self.default
    new(
      extractors: {
        HttpExtractor::STRATEGY => HttpExtractor.new,
        BrowserExtractor::STRATEGY => BrowserExtractor.new
      },
      recorder: ExtractionAttemptRecorder.new
    )
  end

  def initialize(extractors:, recorder:, stats_service: EngineStrategyStats,
                 max_attempts: nil, backoff: nil)
    @extractors = extractors
    @recorder = recorder
    @stats_service = stats_service
    @max_attempts = max_attempts || Rails.application.config.x.max_attempts
    @backoff = backoff || default_backoff
  end

  # search must be a persisted Search (attempts are linked to it).
  def call(query:, engine:, search:, request_id: nil, context: {})
    attempts = []
    strategy = initial_strategy(engine)

    while attempts.length < @max_attempts
      backoff_delay = @backoff.call(attempts.length)
      sleep(backoff_delay) if backoff_delay.positive? && attempts.any?

      extraction = safe_extract(strategy, query, engine, context)
      @recorder.call(search: search, engine: engine, extraction: extraction, request_id: request_id)
      attempts << extraction

      return Outcome.new(extraction: extraction, attempts: attempts) if extraction.success?

      next_strategy = decide_next(strategy, extraction, attempts.length)
      return Outcome.new(extraction: attempts.last, attempts: attempts) unless next_strategy

      strategy = next_strategy
    end

    Outcome.new(extraction: attempts.last, attempts: attempts)
  end

  private

  attr_reader :extractors, :recorder, :stats_service

  def initial_strategy(engine)
    stats = stats_service.for_engine(engine)
    candidates = stats.values.select { |stat| stat.attempts >= EngineStrategyStats::MIN_SAMPLES }
    return HttpExtractor::STRATEGY if candidates.empty?

    winner = candidates.max_by(&:score)
    winner.strategy
  end

  def decide_next(strategy, extraction, attempts_taken)
    return nil if attempts_taken >= @max_attempts

    case strategy
    when BrowserExtractor::STRATEGY
      # A browser is the last resort; transient hiccups get one more go.
      transient_failure?(extraction) ? BrowserExtractor::STRATEGY : nil
    when HttpExtractor::STRATEGY
      if transient_failure?(extraction)
        HttpExtractor::STRATEGY
      elsif ESCALATE_TO_BROWSER.include?(extraction.error_type) && browser_available?(attempts_taken)
        BrowserExtractor::STRATEGY
      end
    end
  end

  def browser_available?(attempts_taken)
    return false unless extractors.key?(BrowserExtractor::STRATEGY)

    attempts_taken < @max_attempts
  end

  def transient_failure?(extraction)
    TRANSIENT_ERRORS.include?(extraction.error_type) ||
      (extraction.http_status.present? && (500..599).cover?(extraction.http_status))
  end

  def safe_extract(strategy, query, engine, context)
    extractors.fetch(strategy).extract(query: query, engine: engine, context: context)
  rescue StandardError => e
    ExtractionResult.failure(
      strategy: strategy,
      error_type: "unknown",
      error_message: "#{e.class}: #{e.message}"
    )
  end

  def default_backoff
    lambda do |attempt_count|
      return 0 if attempt_count.zero?

      # 100ms, 200ms, capped at 400ms. Enough to signal a rate-limiter without
      # annoying real users in local demos.
      [ 0.1 * (2**(attempt_count - 1)), 0.4 ].min
    end
  end
end
