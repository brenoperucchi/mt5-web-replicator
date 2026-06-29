class MagicNumber < ApplicationRecord

  belongs_to :magicable, polymorphic: true
  belongs_to :trace, optional: true
  belongs_to :store, optional: true

  scope :actived, -> { where.not(active_at:nil) }
  scope :disabled, -> { where(active_at:nil) }
end