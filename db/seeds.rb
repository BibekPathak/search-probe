# Development / demo API keys.
#
# Only the BCrypt digest is stored; the plaintext token is printed once here.
# Get the current dev key from this file's output (bin/rails db:seed).
#
#   Development key: dev-key
key_name = "development"
unless ApiKey.exists?(name: key_name)
  ApiKey.create!(name: key_name, key_digest: ApiKey.hash_token("dev-key"))
  Rails.logger.info("Seeded API key 'development' => dev-key (store it somewhere safe; it cannot be recovered later).")
end

# Keep at least one key alive for local demos even if 'development' is deleted.
key_name = "demo"
unless ApiKey.exists?(name: key_name)
  ApiKey.create!(name: key_name, key_digest: ApiKey.hash_token("demo-key"))
end
