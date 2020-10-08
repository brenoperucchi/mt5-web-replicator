require 'lucky_case/string'
class SignTraceSerializer < ActiveModel::Serializer
  attributes :id, :name, :name_id, :active_at
  attributes :orders

  def orders
  	object.orders.ready.map do |message|
  		"Signals::#{@object.name}_Serializer".to_underscore.constantize .new(message)
  	end
	end

  def name
  	object.name.to_underscore
  end


end
