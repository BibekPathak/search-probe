require_relative "boot"

require "rails"
# Pick the frameworks SearchProbe needs and nothing more. ActiveRecord,
# ActionMailer, ActionCable, ActiveStorage, ActionText etc. are intentionally
# not loaded -- MongoDB (via Mongoid) is the only persistence layer.
require "active_model/railtie"
require "active_job/railtie"
require "action_controller/railtie"
require "action_view/railtie"

# Require the gems listed in Gemfile, including any limitations.
Bundler.require(*Rails.groups)

module SearchProbe
  class Application < Rails::Application
    # Initialize configuration defaults for the current Rails version.
    config.load_defaults 8.1

    # All directories under app/ (controllers, models, services, extractors,
    # parsers, jobs, ...) are Zeitwerk-autoloaded and eager-loaded by default.

    # Mongo ODM for generated artifacts (we hand-write models, but be correct).
    config.generators do |g|
      g.orm :mongoid
    end

    # Framework settings are JSON-first; HTML views exist only for /dashboard.
    config.api_only = false

    # Simple shared settings read from the environment (see initializers/app_settings.rb).
  end
end
