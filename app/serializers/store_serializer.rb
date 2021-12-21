class StoreSerializer < ActiveModel::Serializer
  attributes :id, :name, :telegram_api_id, :telegram_api_number, :telegram_api_hash, :server_real, :state
  # has_many :traces
  attributes :traces

  def traces
  	object.traces.active.map do |trace|
      next unless trace.telegram?
      next if trace.telegram_api_id.nil?
  		TraceSerializer.new(trace)
  	end.compact
  end

end