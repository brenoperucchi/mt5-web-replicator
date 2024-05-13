class Plan < ApplicationRecord
  attr_accessor :active, :recurrent

  store :settings, accessors:[:discount]

  has_many :stores

  has_many :plan_items, dependent: :destroy
  # has_many :plan_lines, through: :plan_items, source: :plan_line,  dependent: :destroy
  # has_many :items, :class_name => "PlanPaymentItem", :foreign_key => "plan_payment_id"
  has_many :plan_usages, as: :usageable

  # after_create :create_items

  validates_presence_of :name, :amount

  def recurrent
    true
  end

  def verify_plan_has_items(store)
    %w(Trace Copy Slave).each do |item|
      if plan_items.find_by(name: item, store: store).nil?
        self.plan_items.create(name: item, store: store, amount:self.amount_extra, active: "1", recurrent:true)
      end
    end
  end

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

  def amount_discount
    if self.discount.blank? or self.discount.nil?
      self.amount
    else
      self.amount * (1-discount.to_f/100)
    end
  end

end