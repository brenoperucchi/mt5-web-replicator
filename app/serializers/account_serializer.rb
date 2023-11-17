class AccountSerializer < ActiveModel::Serializer
  attributes :store_state, :store_message, :account_state, :account_margin_mode, :account_mode, :meta_version_accept, 
             :api_server_hostname, :api_debug_mode, :api_freeze_max_time, :api_time_to_check_server, :api_time_max_seconds, :api_slippage, 
             :api_environment_local, :api_store_state, :api_store_message, :api_milliseconds_timer, :api_milliseconds_tick, :api_event_on_timer,
             :api_event_on_tick, :api_debug_mode_level, :api_mfe_mae_display


  def api_debug_mode
    object.api_debug_mode.present? ? object.api_debug_mode.to_b : Store.first.api_debug_mode.to_b                 # Default false
  end

  def api_debug_mode_level
    object.api_debug_mode_level.present? ? object.api_debug_mode_level : Store.first.api_debug_mode_level                     # Default 1 (SendLogFileToServer & MfeMaeDisplay - Slave: GetOrderPriceClose & GetOrderPriceOpen & GetOrderOpenAt)
                          # Default 2 (ApiRequest & ApiTrasmit & CheckServerFreeze)
                          # Default 3 (Print OnTick & OnTimer + Info: mt5_terminal_path/mt5_terminal_data_path/mt5_commondata_path)
  end

  def api_freeze_max_time
    object.api_freeze_max_time.present? ? object.api_freeze_max_time : Store.first.api_freeze_max_time                      # Default 12
  end

  def api_time_to_check_server
    object.api_time_to_check_server.present? ? object.api_time_to_check_server : Store.first.api_time_to_check_server                      # Default 30
  end

  def api_time_max_seconds
    object.api_time_max_seconds.present? ? object.api_time_max_seconds : Store.first.api_time_max_seconds                      # Default 30
  end

  def api_slippage
    object.api_slippage.present? ? object.api_slippage : Store.first.api_slippage                      # Default 30
  end


  def api_environment_local
    object.api_environment_local.present? ? object.api_environment_local.to_b : Store.first.api_environment_local.to_b                    # Default true
  end

  def api_store_state
    object.api_store_state.present? ? object.api_store_state.to_b : Store.first.api_store_state.to_b
  end

  def api_store_message
    object.api_store_message.present? ? object.api_store_message : Store.first.api_store_message
  end

  def api_milliseconds_timer
    object.api_milliseconds_timer.present? ? object.api_milliseconds_timer : Store.first.api_milliseconds_timer                    # Default 3000
  end

  def api_milliseconds_tick
    object.api_milliseconds_tick.present? ? object.api_milliseconds_tick : Store.first.api_milliseconds_tick                    # Default 3000
  end

  def api_event_on_timer
    object.api_event_on_timer.present? ? object.api_event_on_timer.to_b : Store.first.api_event_on_timer.to_b
  end

  def api_event_on_tick
    object.api_event_on_tick.present? ? object.api_event_on_tick.to_b : Store.first.api_event_on_tick.to_b
  end 

  def api_mfe_mae_display
    object.api_mfe_mae_display.present? ? object.api_mfe_mae_display.to_b : Store.first.api_mfe_mae_display.to_b
  end 



  def yaml
    yaml = YAML::load(File.open("#{Rails.root}/config/meta_versions.yml"))
  end

  def meta_version_accept
    params = instance_options[:params]
    @expert_name = params['expert_name']
    @expert_version = params['expert_version'][0..3]
    return (yaml[@expert_name].present? and yaml[@expert_name][@expert_version].present?)
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
    yaml[@expert_name]['disable_msg'].gsub("|version|", @expert_version.gsub('_','.')) unless meta_version_accept
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