require 'lucky_case/string'
class TraceSerializer < ActiveModel::Serializer
  attributes :id, :name, :name_id, :active_at, :telegram_option, :telegram_image
  attributes :orders

  def orders
  	object.orders.ready.map do |order|
  		"Signals::#{@object.name}Serializer".to_underscore.constantize.new(order)
  	end
	end

  def name
  	object.name
  end


end
