class AccountSerializer < ActiveModel::Serializer
  attributes :store_state, :store_message, :account_state, :account_margin_mode, :account_mode

  def store_state
    object.store.state
  end

  def store_message
    ""  
  end

  def account_state
    object.state
  end

  def account_margin_mode
    object.meta_margin_mode
  end

  def account_mode
    object.meta_mode
  end

  # attributes :id, :name, :telegram_api_id, :telegram_api_number, :telegram_api_hash, :server_real, :state
  # # has_many :traces
  # attributes :traces

  # def traces
  # 	object.traces.active.map do |trace|
  #     next unless trace.telegram?
  #     next if trace.telegram_api_id.nil?
  # 		TraceSerializer.new(trace)
  # 	end.compact
  # end

end