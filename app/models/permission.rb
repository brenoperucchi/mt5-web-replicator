class Permission < ApplicationRecord
  belongs_to :account
  belongs_to :trace
end
