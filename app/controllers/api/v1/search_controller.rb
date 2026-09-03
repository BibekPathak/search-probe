module Api
  module V1
    # Thin controller: validate params are forwarded to SearchService, JSON is
    # shaped here, HTTP status codes map the domain error taxonomy.
    class SearchController < BaseController
      def show
        outcome = SearchService.new.call(
          query: params[:q],
          engine: params[:engine],
          request_id: request.request_id,
          force_refresh: force_refresh?,
          context: { simulate: params[:simulate], simulate_order: params[:simulate_order] }
        )

        render_search(outcome)
      rescue Errors::ValidationError => e
        render_error("validation_error", e.code, e.message, :bad_request)
      rescue Errors::UnsupportedEngine => e
        render_error("unsupported_engine", "unsupported_engine",
                     "#{e.engine} is not a supported engine (#{Search::ENGINES.join(', ')}).", :not_found)
      rescue Errors::ExtractionFailed => e
        payload = {
          error: {
            code: "extraction_failed",
            type: e.error_type,
            message: e.message
          }
        }
        payload[:error][:http_status] = e.http_status if e.http_status
        render json: payload, status: :internal_server_error
      rescue StandardError => e
        Rails.logger.error({ event: "search.unhandled_error", error: "#{e.class}: #{e.message}" })
        render json: { error: { code: "internal_error", type: "unknown", message: "An unexpected error occurred." } },
               status: :internal_server_error
      end

      private

      def render_search(outcome)
        render json: {
          query: outcome.query,
          engine: outcome.engine,
          results: outcome.results,
          metadata: {
            cached: outcome.cached,
            latency_ms: outcome.latency_ms,
            strategy: outcome.strategy,
            attempts: outcome.attempts
          }
        }, status: :ok
      end

      def force_refresh?
        %w[true 1 yes].include?(params[:force_refresh].to_s.downcase)
      end
    end
  end
end
