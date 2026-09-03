module Api
  module V1
    # Shared JSON API plumbing: API-key authentication then per-key rate
    # limiting. Every controller under /api/v1 inherits from here, so new
    # endpoints get the same protection by default.
    class BaseController < ApplicationController
      before_action :authenticate_api_key!
      before_action :enforce_rate_limit!

      private

      def authenticate_api_key!
        token = request.headers["X-API-Key"].to_s
        @api_key = ApiKey.authenticate(token)

        return if @api_key

        render_error("unauthorized", "invalid_api_key",
                     token.blank? ? "Missing X-API-Key header." : "Invalid API key.", :unauthorized)
      end

      def enforce_rate_limit!
        result = RateLimiter.check(scope: @api_key.id.to_s, limit: Rails.application.config.x.rate_limit_per_minute)

        return if result.allowed

        StructuredLog.emit("rate_limit.exceeded", scope: @api_key.id.to_s, retry_after_seconds: result.retry_after_seconds)
        response.set_header("Retry-After", result.retry_after_seconds.to_s)
        render json: {
          error: {
            code: "rate_limited",
            type: "rate_limited",
            message: "Rate limit exceeded. Retry after #{result.retry_after_seconds}s."
          }
        }, status: :too_many_requests
      end

      def render_error(code, type, message, status)
        render json: { error: { code: code, type: type, message: message } }, status: status
      end
    end
  end
end
