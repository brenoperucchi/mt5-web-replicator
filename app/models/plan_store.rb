class PlanStore < ApplicationRecord
  belongs_to :store
  belongs_to :plan_item
end
