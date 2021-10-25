class Logging < ApplicationRecord
  belongs_to :user, optional: true
  belongs_to :loggerable, polymorphic: true
end
