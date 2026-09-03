module Api
  module V1
    # Thin controller: validate params are forwarded to SearchService, JSON is
    # shaped here, HTTP status codes map the domain error taxonomy.
    class SearchController < ApplicationController
      def show
        outcome = SearchService.new.call(
          query: params[:q],
          engine: params[:engine],
          request_id: request.request_id,
          context: { simulate: params[:simulate] }
        )

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
      rescue Errors::ValidationError => e
        render_error("validation_error", e.code, e.message, :bad_request)
      rescue Errors::UnsupportedEngine => e
        render_error("unsupported_engine", "unsupported_engine",
                     "#{e.engine} is not a supported engine (#{Search::ENGINES.join(', ')}).", :not_found)
      rescue Errors::ExtractionFailed => e
        render_error("extraction_failed", e.error_type, e.message, :internal_server_error, http_status: e.http_status)
      rescue StandardError => e
        Rails.logger.error({ event: "search.unhandled_error", error: "#{e.class}: #{e.message}" })
        render_error("internal_error", "unknown", "An unexpected error occurred.", :internal_server_error)
      end

      private

      def render_error(meta_code, error_type, message, status, http_status: nil)
        payload = {
          error: {
            code: meta_code,
            type: error_type,
            message: message
          }
        }
        payload[:error][:http_status] = http_status if http_status
        render json: payload, status: status
      end
    end
  end
end
