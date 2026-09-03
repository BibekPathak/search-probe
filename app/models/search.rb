class Search
  include Mongoid::Document
  include Mongoid::Timestamps::Created

  # Engines the simulator understands. Extenders can add real adapters behind
  # the same interface without touching this list.
  ENGINES = %w[google bing duckduckgo].freeze

  STATUSES = %w[queued running completed failed].freeze

  field :query, type: String
  field :engine, type: String
  field :status, type: String, default: "completed"
  field :cache_hit, type: Boolean, default: false
  field :latency_ms, type: Integer
  field :strategy, type: String
  field :error_type, type: String

  has_many :search_results, dependent: :destroy
  has_many :extraction_attempts, dependent: :destroy

  validates :query, presence: true, length: { maximum: 500 }
  validates :engine, presence: true, inclusion: { in: ENGINES }
  validates :status, presence: true, inclusion: { in: STATUSES }

  index({ query: 1 })
  index({ engine: 1 })
  index({ created_at: -1 })
  index({ query: 1, engine: 1 })

  # Most recent completed search for the same query + engine, excluding self.
  # Used by the SERP-diff feature.
  def self.previous_for(query:, engine:, not_id: nil)
    criteria = where(query: query, engine: engine, status: "completed").order_by(created_at: :desc)
    criteria = criteria.where(:id.ne => not_id) if not_id
    criteria.first
  end
end
