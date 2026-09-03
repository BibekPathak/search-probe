# Runs a queued Search to completion in the background (ActiveJob).
# SearchService.perform handles every state transition and never raises for
# expected extraction failures, so a failed page just leaves the Search in
# status "failed" for the client to poll.
class SearchJob < ApplicationJob
  queue_as :default

  def perform(search_id)
    search = Search.find_by(id: search_id)
    return if search.nil?

    SearchService.new.perform(search: search, request_id: search.id.to_s)
  end
end
