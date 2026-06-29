class Permission < ApplicationRecord
  # attr_reader :name

  belongs_to :account, optional:true
  belongs_to :trace, optional:true
  belongs_to :plan_usage, optional:true#, as: :resourceable, optional:true
  belongs_to :customer_plan, optional:true#, as: :resourceable, optional:true

   def name
    "Trace ##{self.trace.name} - Account ##{self.account.try(:name)}"
  end

end
