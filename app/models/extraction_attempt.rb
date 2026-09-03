class ExtractionAttempt
  include Mongoid::Document
  include Mongoid::Timestamps::Created

  # Canonical failure taxonomy consumed by the planner and the metrics layer.
  ERROR_TYPES = %w[
    timeout
    rate_limited
    blocked
    captcha
    parse_error
    network_error
    unknown
  ].freeze

  STRATEGIES = %w[http browser].freeze

  field :engine, type: String
  field :strategy, type: String
  field :status, type: String # success | failure
  field :http_status, type: Integer
  field :latency_ms, type: Integer
  field :error_type, type: String
  field :error_message, type: String

  belongs_to :search, optional: true

  validates :engine, presence: true
  validates :strategy, presence: true, inclusion: { in: STRATEGIES }
  validates :status, presence: true, inclusion: { in: %w[success failure] }
  validates :error_type, inclusion: { in: ERROR_TYPES }, allow_nil: true
  validates :error_message, length: { maximum: 500 }

  index({ created_at: -1 })
  index({ engine: 1, strategy: 1 })
  index({ error_type: 1 })
  index({ search_id: 1 })
end
