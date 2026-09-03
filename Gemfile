source "https://rubygems.org"

ruby "3.3.12"

# --- Core framework (selective railties loaded in config/application.rb) ---
gem "rails", "~> 8.1.3"
gem "puma", ">= 5.0"

# --- Persistence: MongoDB via Mongoid (document-oriented ODM) ---
gem "mongoid", "~> 9.1"

# --- Extraction / parsing ---
gem "nokogiri", ">= 1.16"

# --- Security: BCrypt hashes for API keys ---
gem "bcrypt", "~> 3.1"

# --- Bundled stdlib gems pinned for Ruby 3.3 stability ---
gem "bigdecimal"
gem "benchmark"
gem "json"
gem "logger"
gem "ostruct"

group :development, :test do
  gem "rspec-rails", "~> 8.0"
  gem "factory_bot_rails", "~> 6.5"
  gem "webmock", "~> 3.26"
  # Default Rails style guide (rubocop + rails cops). Deliberately omakase.
  gem "rubocop-rails-omakase", "~> 1.1"
end
