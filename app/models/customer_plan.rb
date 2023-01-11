class CustomerPlan < ApplicationRecord
  attr_accessor :active
  enum kind: {fixed: 0, percent: 1}

  belongs_to :store, optional:true
  has_many :customers
  has_many :plan_usages, as: :usageable

  scope :active,  -> { where.not(active_at:nil) }

  validates_presence_of [:name, :amount], :if => proc { |obj| !Current.user.nil? and Current.user.userable.role == "customer" }
  validates_presence_of :active, :if => :validate_active_at

  accepts_nested_attributes_for :customers

  def validate_active_at
    self.active == false and self.class.active.present? and self.id == self.class.active.try(:first).try(:id)
  end

  def active=(attribute)
    if attribute == "1" and not self.read_attribute(:active_at) == 1
      if self.class.active.present?
        self.class.active.first.update_column(:active_at, nil) if self.class.active.try(:first).try(:id) != self.id
      end
      self.active_at = DateTime.now
    else
      self.active_at = nil
    end
  end

  def active
    self.read_attribute(:active_at).nil? ? false : true 
  end

end
