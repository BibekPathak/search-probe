class RateLimitEntry
  include Mongoid::Document
  include Mongoid::Timestamps::Created

  # Fixed-window counter. One document per (scope, window_start); counts are
  # bumped atomically with find_one_and_update(upsert). The TTL index expires
  # old windows so the collection never needs manual pruning.
  field :scope, type: String
  field :window_start, type: Time
  field :count, type: Integer, default: 0

  index({ scope: 1, window_start: 1 })
  index({ window_start: 1 }, expire_after_seconds: 120)
end
