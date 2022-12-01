class PlanItem < ApplicationRecord
  attr_accessor :active, :amount_extra

  belongs_to :plan
  belongs_to :store, optional:true
  has_many :plan_usages, as: :usageable

  def active=(attribute)
    if attribute != "1" 
      self.active_at = nil 
    else 
      self.active_at = DateTime.now if active_at.nil?
    end
  end

  def active
    self.active_at.nil? ? false : true
  end

end
