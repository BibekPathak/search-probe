# Fixed-window API rate limiter.
#
# Scope is usually the API key id (or an IP when we ever allow anonymous
# traffic). Limits are enforced in-process against Mongo via atomic upserts, so
# it stays correct across Puma threads without extra infrastructure.
class RateLimiter
  Result = Struct.new(:allowed, :retry_after_seconds, keyword_init: true)

  WINDOW_SECONDS = 60

  def self.check(scope:, limit:, now: Time.current.to_i)
    new(scope: scope, limit: limit, now: now).check
  end

  def initialize(scope:, limit:, now: Time.current.to_i)
    @scope = scope
    @limit = limit.to_i
    @now = now
  end

  def check
    window = @now - (@now % WINDOW_SECONDS)
    window_start = Time.at(window)

    document = RateLimitEntry.collection.find_one_and_update(
      { scope: @scope, window_start: window_start },
      { "$inc" => { count: 1 }, "$setOnInsert" => { created_at: Time.current } },
      upsert: true,
      return_document: :after
    )

    count = document["count"].to_i
    if count <= @limit
      Result.new(allowed: true, retry_after_seconds: 0)
    else
      retry_after = WINDOW_SECONDS - (@now % WINDOW_SECONDS)
      Result.new(allowed: false, retry_after_seconds: retry_after)
    end
  rescue Mongo::Error, Mongoid::Errors::MongoidError
    # Fail-open on storage problems: availability beats strict throttling here.
    Result.new(allowed: true, retry_after_seconds: 0)
  end
end
