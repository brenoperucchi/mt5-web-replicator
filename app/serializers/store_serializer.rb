class StoreSerializer < ActiveModel::Serializer
  attributes :id, :name
  # has_many :traces
  attributes :traces



  def traces
  	object.traces.active.map do |trace|
  		SignTraceSerializer.new(trace)
  	end
  end

end
