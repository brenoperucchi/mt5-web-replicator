class PlanItem < ApplicationRecord
  attr_accessor :active, :amount_extra

  belongs_to :plan
  # belongs_to :store, optional:true
  has_many :plan_stores, dependent: :destroy
  has_many :stores, through: :plan_stores, source: :store, dependent: :destroy
  
  has_many :plan_usages, as: :usageable

  scope :active, -> { where.not(active_at: nil) }

  def active=(attribute)
    if attribute != "1" 
      self.active_at = nil 
    else 
      self.active_at = DateTime.current if active_at.nil?
    end
  end

  def active
    self.active_at.nil? ? false : true
  end

end
