module ApiAuthHelpers
  TEST_TOKEN = "test-key"

  # Lazily creates the shared spec API key for the current example and returns
  # request headers carrying it.
  def auth_headers(token: TEST_TOKEN, name: "spec")
    ApiKey.create!(name: name, key_digest: ApiKey.hash_token(token)) unless ApiKey.exists?(name: name)
    { "X-API-Key" => token }
  end
end

RSpec.configure do |config|
  config.include ApiAuthHelpers, type: :request
end
