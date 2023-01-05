class CustomerPlan < ApplicationRecord
  belongs_to :store, optional:true
  has_many :customers
end
