class SearchResult
  include Mongoid::Document

  RESULT_TYPES = %w[organic].freeze

  field :position, type: Integer
  field :title, type: String
  field :url, type: String
  field :snippet, type: String
  field :result_type, type: String, default: "organic"

  belongs_to :search

  validates :search, presence: true
  validates :position, presence: true, numericality: { only_integer: true, greater_than: 0 }
  validates :title, presence: true
  validates :url, presence: true
  validates :result_type, presence: true, inclusion: { in: RESULT_TYPES }

  index({ search_id: 1 })
  index({ search_id: 1, position: 1 })

  def to_api_hash
    {
      position: position,
      title: title,
      url: url,
      snippet: snippet,
      result_type: result_type
    }
  end
end
