class StoreSerializer < ActiveModel::Serializer
  attributes :id, :name
  # has_many :traces
  attributes :traces



  def traces
  	object.traces.active.map do |trace|
  		TraceSerializer.new(trace)
  	end
  end

end
