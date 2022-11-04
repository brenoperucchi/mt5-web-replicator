class AccountSerializer < ActiveModel::Serializer
  attributes :store_state, :store_message, :account_state, :account_margin_mode, :account_mode, :api_server_hostname, :meta_version_accept


  def yaml
    yaml = YAML::load(File.open("#{Rails.root}/config/meta_versions.yml"))
  end

  def meta_version_accept
    params = instance_options[:params]
    yaml[params['expert_name']][params['expert_version']] == "OK" ? true : false
  end

  def store_state
    if meta_version_accept
      object.store.state
    else
      'disable'
    end  
  end

  def store_message
    params = instance_options[:params]
    yaml[params['expert_name']]['disable_msg'].gsub("|version|", params['expert_version'].gsub('_','.')) unless meta_version_accept
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

  def api_server_hostname
    object.api_server_hostname(instance_options[:params])
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