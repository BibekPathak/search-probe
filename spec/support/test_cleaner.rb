module SearchProbe
  # Drops every collection in the test database. Simple, deterministic, and
  # fast enough at this scale -- no database_cleaner dependency required.
  module TestCleaner
    COLLECTIONS = %w[
      searches
      search_results
      extraction_attempts
      api_keys
      rate_limit_entries
    ].freeze

    module_function

    def clean!
      db = Mongoid.default_client.database
      db.collections.each do |collection|
        next unless COLLECTIONS.include?(collection.name)

        collection.delete_many
      end
    end
  end
end
