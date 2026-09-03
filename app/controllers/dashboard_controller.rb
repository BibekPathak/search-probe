class DashboardController < ApplicationController
  # Minimal operational dashboard. Data is server-rendered for a usable first
  # paint and then kept fresh by the inline JavaScript polling the JSON API.
  # Open (unauthenticated) on purpose: it is a local dev/demo tool.
  def show
    @metrics = MetricsService.call
    @attempts = ExtractionAttempt.desc(:created_at).limit(15)
  end
end
