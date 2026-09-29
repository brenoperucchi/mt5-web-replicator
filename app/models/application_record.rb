class ApplicationRecord < ActiveRecord::Base
  self.abstract_class = true

  # Columns that must never be searchable/sortable through ransack: credentials,
  # password material, provider tokens, raw provider responses and serialized
  # settings (which hold per-store secrets such as stripe_api_secret,
  # telegram_bot_token and telegram_api_hash).
  RANSACK_ATTRIBUTE_DENYLIST = %w[
    encrypted_password reset_password_token
    api_token webhook_token
    settings response
  ].freeze

  # Associations that lead to credentials (payments -> api_token/webhook_token,
  # users/user -> password data) or across stores into other stores' customer
  # PII (e.g. order.trace.stores.customers.user.email). No admin/control
  # filter searches through them.
  RANSACK_ASSOCIATION_DENYLIST = %w[payments users user tokens stores customers].freeze

  # Ransack 4 requires explicit allowlists. Search is only exposed through the
  # authenticated admin/ and control/ dashboards, so allow every column and
  # association except the sensitive ones above.
  def self.ransackable_attributes(_auth_object = nil)
    authorizable_ransackable_attributes - RANSACK_ATTRIBUTE_DENYLIST
  end

  def self.ransackable_associations(_auth_object = nil)
    authorizable_ransackable_associations - RANSACK_ASSOCIATION_DENYLIST
  end
end
