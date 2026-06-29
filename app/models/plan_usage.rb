class PlanUsage < ApplicationRecord
  attr_accessor :amount, :proportional, :usage_seconds, :description, :amount_proportional, :amount_profit

  serialize :plan_serializer, JSON

  belongs_to :usageable,    polymorphic: true
  belongs_to :resourceable, polymorphic: true
  belongs_to :trace,        class_name: 'Trace', optional: true
  belongs_to :store

  has_many :invoice_items

  def proporcional_calculate(date_today=nil, amount_use=nil, proporcional=false, contract_volume=nil)
    changes = false
    date_today       ||= DateTime.current
    amount_use       ||= usageable.amount_use || plan_serializer["amount"].to_f
    contract_volume  ||= 1

    datetime_reference = proporcional ? DateTime.current : date_today

    days_month = Time.days_in_month(date_today.month)
    month_seconds = (days_month * 24 * 3600).to_f
    
    if self.disable_at.present?
      if active_at.month != date_today.month or active_at.year != date_today.year
        usage_seconds = (self.disable_at.to_time - date_today.beginning_of_month.to_time)
      else
        usage_seconds = (self.disable_at.to_time - self.active_at.to_time)
      end
    else
      usage_seconds ||= (date_today.end_of_month.to_time - datetime_reference.to_time)
    end
    usage_seconds = usage_seconds.round
    if usage_seconds < month_seconds
      self.proportional = (usage_seconds / month_seconds).abs
      self.amount_proportional = amount_use * proportional * contract_volume
      changes = true
    elsif usage_seconds >= month_seconds
      self.proportional = 1
      self.amount_proportional = amount_use * proportional * contract_volume
      changes = true
    end
    self.amount_proportional = (usageable.try(:payment).try(:min_amount).to_f > self.amount_proportional) ? usageable.try(:payment).try(:min_amount) : self.amount_proportional
    self.amount = amount_use
    
    return self
  end

  def update_next_charged
    days = DateTime.current.day > 15 ? 15 : 0
    self.charged_at = (DateTime.current + days + usageable.class.charge_recurrences[usageable.charge_recurrence.to_s].months).beginning_of_month
    self.save
  end

  def amount_calculate(date_today=nil, month_proporcional=nil, contract_volume=nil, data_profit)
    date_today ||= DateTime.current
    account      = self.resourceable
    self.proporcional_calculate(date_today, usageable.amount_use, month_proporcional, contract_volume)
    if usageable.fixed?# and usageable.monthly?
      amount_use = self.amount_proportional
    elsif usageable.percent?
      resource = account || trace
      resource.search_date_begin = date_today.beginning_of_month
      resource.search_date_end = date_today.end_of_month
      amount_use = data_profit * (usageable.amount_use.to_f / 100)
    end
    
    self.amount              = usageable.amount
    self.amount_profit       = data_profit
    self.amount_proportional = amount_use

    return self
  end

end