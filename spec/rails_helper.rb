require "spec_helper"

ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"

abort("The Rails environment is running in production mode!") if Rails.env.production?

require "rspec/rails"
require "webmock/rspec"

# Ensure our mocks never accidentally hit a live Mongo/network target.
WebMock.disable_net_connect!(allow_localhost: true)

Dir[Rails.root.join("spec/support/**/*.rb")].sort.each { |f| require f }

RSpec.configure do |config|
  config.use_transactional_examples = false

  config.include FactoryBot::Syntax::Methods

  # Clean every collection between examples so tests are independent.
  config.before(:each) do
    SearchProbe::TestCleaner.clean!
    Rails.cache.clear
    WebMock.reset!
    # Tests never talk to a live backend or worker; point extractors at the
    # stubbed hosts.
    Rails.application.config.x.simulator_base_url = "http://localhost:3000"
    Rails.application.config.x.browser_worker_url = "http://localhost:8001"
  end

  config.infer_spec_type_from_file_location!
  config.filter_rails_from_backtrace!
end
