class HealthController < ApplicationController
  def show
    database =
      begin
        Mongoid.default_client.command(ping: 1)
        "ok"
      rescue StandardError
        "error"
      end

    render json: {
      status: database == "ok" ? "ok" : "degraded",
      database: database
    }, status: database == "ok" ? :ok : :service_unavailable
  end
end
