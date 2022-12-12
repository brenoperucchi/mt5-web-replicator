class PlanUsage < ApplicationRecord
  attr_accessor :amount, :proportional, :usage_seconds, :description

  belongs_to :usageable,    polymorphic: true
  belongs_to :resourceable, polymorphic: true
  belongs_to :store


  def calculate_usage(date_today=nil)
    changes = false
    # date_today ||= DateTime.now
    days_month = Time.days_in_month(date_today.month)
    amount_use = usageable.amount
    month_seconds = days_month * 24 * 3600

    if self.disable_at.present?
      if active_at.month != date_today.month or active_at.year != date_today.year
        usage_seconds = (self.disable_at.to_time - date_today.beginning_of_month.to_time)
      else
        usage_seconds = (self.disable_at.to_time - self.active_at.to_time)
      end
    else
      usage_seconds ||= (date_today.end_of_month.to_time - self.created_at.to_time)
    end

    if usage_seconds < month_seconds
      self.proportional = (usage_seconds / month_seconds)
      self.amount = amount_use * proportional
      changes = true
    elsif usage_seconds > month_seconds
      self.proportional = 1
      self.amount = amount_use * proportional
      changes = true
    end
    if changes
      self.description = "#{usageable.class.name} ID ##{usageable.id} - #{self.resourceable.class.name} ##{self.resourceable.id} - PlanUsage ID ##{self.id}\r\n"
      self.description << "#{usageable.class.name}: #{usageable.name} - Proportional: #{self.proportional} - amount: #{amount_use} - seconds: #{usage_seconds}\r\n"
    end
    return changes
  end


end