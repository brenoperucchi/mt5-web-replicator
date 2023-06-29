class PlanUsage < ApplicationRecord
  attr_accessor :amount, :proportional, :usage_seconds, :description

  serialize :plan_serializer, JSON

  belongs_to :usageable,    polymorphic: true
  belongs_to :resourceable, polymorphic: true
  belongs_to :store


  def calculate_usage(date_today=nil, amount_use=nil)
    changes = false
    amount_use ||= plan_serializer["amount"].to_f || usageable.amount
    date_today ||= DateTime.now
    days_month = Time.days_in_month(date_today.month)
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
      self.description = "#{usageable.class.name} ID ##{usageable.id} - #{self.resourceable_type} ##{self.resourceable_id} - PlanUsage ID ##{self.id}\r\n"
      self.description << "#{usageable.class.name}: #{usageable.name} - Proportional: #{self.proportional} - amount: #{self.amount} - seconds: #{usage_seconds}\r\n"
    end
    return changes
  end

  def update_next_charged
    days = DateTime.now.day > 15 ? 15 : 0
    self.charged_at = (DateTime.now + days + usageable.class.charge_recurrences[usageable.charge_recurrence.to_s].months).beginning_of_month
    self.save
  end


end


# def calculate_usage(date_today = nil, amount_use = nil)
#   # Estabelece valores padrão para data e quantidade se não forem fornecidos
#   amount_use ||= usageable.amount
#   date_today ||= DateTime.now

#   # Calcula a quantidade de segundos em um mês
#   days_month = Time.days_in_month(date_today.month)
#   month_seconds = days_month * 24 * 3600

#   # Calcula os segundos de uso baseado na data de desativação, se existir
#   if disable_at.present?
#     usage_seconds = if active_at.month != date_today.month or active_at.year != date_today.year
#                       # Se o mês ou ano de ativação são diferentes da data atual, 
#                       # o uso é calculado a partir do início do mês até a data de desativação
#                       disable_at.to_time - date_today.beginning_of_month.to_time
#                     else
#                       # Se o mês e o ano são os mesmos, 
#                       # o uso é calculado a partir da data de ativação até a data de desativação
#                       disable_at.to_time - active_at.to_time
#                     end
#   else
#     # Se não há data de desativação, 
#     # o uso é calculado a partir da data de criação até o final do mês atual
#     usage_seconds ||= date_today.end_of_month.to_time - created_at.to_time
#   end

#   # Calcula a proporção de uso e a quantidade baseada nos segundos de uso
#   # Nota: o uso não pode exceder 1 mês, então a proporção é limitada a 1
#   new_proportional = [1, usage_seconds / month_seconds].min
#   new_amount = amount_use * new_proportional

#   # Verifica se a proporção ou a quantidade mudaram. 
#   # Se não houver mudanças, retorna falso para indicar que nenhuma atualização é necessária
#   return false if proportional == new_proportional && amount == new_amount

#   # Atualiza a proporção e a quantidade
#   self.proportional = new_proportional
#   self.amount = new_amount

#   # Atualiza a descrição com os novos detalhes
#   self.description = "#{usageable.class.name} ID ##{usageable.id} - #{resourceable_type} ##{resourceable_id} - PlanUsage ID ##{id}\r\n"
#   self.description << "#{usageable.class.name}: #{usageable.name} - Proportional: #{proportional} - amount: #{amount} - seconds: #{usage_seconds}\r\n"

#   # Retorna verdadeiro para indicar que houve uma atualização
#   true
# end
