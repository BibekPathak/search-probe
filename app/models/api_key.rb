class ApiKey
  include Mongoid::Document
  include Mongoid::Timestamps::Created

  # Only a BCrypt digest of the key is ever persisted. The plaintext is shown
  # exactly once at creation (see db/seeds.rb) and can never be recovered from
  # the database.
  field :name, type: String
  field :key_digest, type: String
  field :active, type: Boolean, default: true

  validates :name, presence: true, uniqueness: true
  validates :key_digest, presence: true

  index({ name: 1 }, unique: true)
  index({ key_digest: 1 })

  def self.hash_token(token)
    BCrypt::Password.create(token, cost: bcrypt_cost)
  end

  # Returns the matching active ApiKey for a presented token, or nil.
  def self.authenticate(token)
    return nil if token.blank?

    where(active: true).each do |key|
      return key if BCrypt::Password.new(key.key_digest) == token
    end
    nil
  end

  # Low cost in non-production keeps local dev + specs fast while storing the
  # same salted-hash mechanism production uses.
  def self.bcrypt_cost
    Rails.env.production? ? BCrypt::Engine::DEFAULT_COST : BCrypt::Engine::MIN_COST
  end
end
