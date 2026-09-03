module Api
  module V1
    # Recent extraction attempts, newest first. Backs the dashboard's live
    # attempts table (and is handy for debugging the planner directly).
    class AttemptsController < BaseController
      def index
        limit = [ [ params.fetch(:limit, 15).to_i, 1 ].max, 50 ].min
        attempts = ExtractionAttempt.desc(:created_at).limit(limit)

        render json: { attempts: attempts.map { |attempt| attempt_payload(attempt) } }, status: :ok
      end

      private

      def attempt_payload(attempt)
        {
          id: attempt.id.to_s,
          created_at: attempt.created_at&.iso8601,
          search_id: attempt.search_id&.to_s,
          query: attempt.search&.query,
          engine: attempt.engine,
          strategy: attempt.strategy,
          status: attempt.status,
          http_status: attempt.http_status,
          latency_ms: attempt.latency_ms,
          error_type: attempt.error_type,
          error_message: attempt.error_message
        }
      end
    end
  end
end
