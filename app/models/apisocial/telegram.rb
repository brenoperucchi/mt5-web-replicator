# require 'tdlib-ruby'
# Thread.current.report_on_exception = false
# Thread.report_on_exception = false

class Apisocial::Telegram
  def initialize
    TD.configure do |config|
      config.lib_path = '/Users/brenoperucchi/tdlib/build/'

      config.client.api_id = 980209
      config.client.api_hash = '03062326232cb23c6770e7a735c2dae2'
    end

    TD::Api.set_log_verbosity_level(1)
    TD::Api.set_log_file_path('/Users/brenoperucchi/tdlib.log')


    @client = TD::Client.new
    @client.set_tdlib_parameters({
       :api_id=>980209,
       :api_hash=>"03062326232cb23c6770e7a735c2dae2",
       :use_test_dc=>false,
       :database_directory=>"/Users/brenoperucchi/.tdlib-ruby/db",
       :files_directory=>"/Users/brenoperucchi/.tdlib-ruby/data",
       :use_file_database=>true,
       :use_chat_info_database=>true,
       :use_secret_chats=>true,
       :use_message_database=>true,
       :system_language_code=>"en",
       :device_model=>"Ruby TD client",
       :system_version=>"Unknown",
       :application_version=>"1.0",
       :enable_storage_optimizer=>true,
       :ignore_file_names=>false})
      @client.on(TD::Types::Update::AuthorizationState) do |update|
        @state = case update.authorization_state
                when TD::Types::AuthorizationState::WaitPhoneNumber
                  :wait_phone_number
                when TD::Types::AuthorizationState::WaitCode
                  :wait_code
                when TD::Types::AuthorizationState::WaitPassword
                  :wait_password
                when TD::Types::AuthorizationState::Ready
                  :ready
                else
                  nil
                end
      end
      
    end

    def client
      # binding.pryAp.c
      return @client.connect.result[1]
    end
end