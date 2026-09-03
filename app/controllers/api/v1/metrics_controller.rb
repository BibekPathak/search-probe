module Api
  module V1
    class MetricsController < BaseController
      def index
        render json: MetricsService.call, status: :ok
      end
    end
  end
end
