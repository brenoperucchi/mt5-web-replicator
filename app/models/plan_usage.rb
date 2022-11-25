class PlanUsage < ApplicationRecord
  attr_accessor :amount, :proportional, :usage_seconds

  belongs_to :usageable,    polymorphic: true
  belongs_to :resourceable, polymorphic: true
  belongs_to :store


  def calculate_usage
    date_today = DateTime.now
    days_month = Time.days_in_month(date_today.month)
    amount_use = usageable.amount
    month_seconds = days_month * 24 * 3600
    invoice_name = "#{store.id}-#{Time.zone.now.strftime("%Y-%m")}"
    invoice = store.invoices.find_or_create_by(name: invoice_name, store:store)

    if usageable_type == "Plan" 
      if self.disable_at.present?
        usage_seconds = (self.disable_at.to_time - self.active_at.to_time)
      end
    end
    usage_seconds ||= (date_today.end_of_month.to_time - self.created_at.to_time)
    

    if not usageable.recurrent or not self.charged_at.nil?
      return if self.charged_at.try(:month) <= date_today.month
    end
    puts "Usage ID##{self.id}"
    if usage_seconds < month_seconds
      puts "usage_seconds #{usage_seconds} < #{month_seconds} month_seconds"
      self.proportional = (usage_seconds / month_seconds)
      self.amount = amount_use * proportional
    elsif usage_seconds > month_seconds
      puts "usage_seconds #{usage_seconds} > #{month_seconds} month_seconds"
      self.proportional = 1
      self.amount = amount_use * proportional
    end
    description = "#{usageable.class.name} ID ##{usageable.id} - #{self.resourceable.class.name} ##{self.resourceable.id} - PlanUsage ID ##{self.id}\r\n"
    description << "#{usageable.class.name}: #{usageable.name} - Proportional: #{self.proportional} - amount: #{amount_use} - seconds: #{usage_seconds}\r\n"
    invoice.items.find_or_create_by(name: "month_#{self.handle.try(:downcase)}",  amount: self.amount, description: description) 
    invoice.balance_update
    self.update(charged_at: DateTime.now)
    return self
  end


end