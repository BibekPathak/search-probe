# Compares two SERPs for the same query + engine (see GET
# /api/v1/searches/:id/diff). Results are matched by canonical URL:
#
#   added            results present now but not before
#   removed          results present before but not now
#   position_changes same result that moved between positions
class SerpDiff
  Result = Struct.new(:added, :removed, :position_changes, keyword_init: true)

  def self.between(current:, previous:)
    new(current: current, previous: previous).call
  end

  def initialize(current:, previous:)
    @current = current
    @previous = previous
  end

  def call
    previous_by_url = previous_results.index_by { |r| r[:url] }
    current_by_url = current_results.index_by { |r| r[:url] }

    added = current_results.reject { |r| previous_by_url.key?(r[:url]) }
    removed = previous_results.reject { |r| current_by_url.key?(r[:url]) }
    position_changes = []

    current_results.each do |result|
      earlier = previous_by_url[result[:url]]
      next unless earlier
      next if earlier[:position] == result[:position]

      position_changes << {
        title: result[:title],
        url: result[:url],
        from: earlier[:position],
        to: result[:position]
      }
    end

    Result.new(
      added: added,
      removed: removed,
      position_changes: position_changes
    )
  end

  private

  attr_reader :current, :previous

  def current_results
    current.search_results.order_by(position: :asc).map(&:to_api_hash)
  end

  def previous_results
    previous.search_results.order_by(position: :asc).map(&:to_api_hash)
  end
end
