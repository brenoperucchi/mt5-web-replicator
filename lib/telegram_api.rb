# require 'tdlib-ruby'
# Thread.current.report_on_exception = false
# Thread.report_on_exception = false

class TelegramApi
  def initialize
    TD.configure do |config|
      config.lib_path = '/usr/local/Cellar/tdlib/1.6.0/include/td/'

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
       :system_version=>"test",
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
      return @client.connect.result[1]
    end
end

# require 'tdlib-ruby'
# require 'concurrent'

# class TelegramApi
#   def initialize
#     TD.configure do |config|
#       config.lib_path = '/usr/local/Cellar/tdlib/1.6.0/include/td/'

#       config.client.api_id = 980209
#       config.client.api_hash = '03062326232cb23c6770e7a735c2dae2'
#     end

#     TD::Api.set_log_verbosity_level(1)
#     TD::Api.set_log_file_path('/Users/brenoperucchi/tdlib.log')


#     @client = TD::Client.new
#     @client.set_tdlib_parameters({
#        :api_id=>980209,
#        :api_hash=>"03062326232cb23c6770e7a735c2dae2",
#        :use_test_dc=>false,
#        :database_directory=>"/Users/brenoperucchi/.tdlib-ruby/db",
#        :files_directory=>"/Users/brenoperucchi/.tdlib-ruby/data",
#        :use_file_database=>true,
#        :use_chat_info_database=>true,
#        :use_secret_chats=>true,
#        :use_message_database=>true,
#        :system_language_code=>"en",
#        :device_model=>"Ruby TD client",
#        :system_version=>"test",
#        :application_version=>"1.0",
#        :enable_storage_optimizer=>true,
#        :ignore_file_names=>false})
#       @client.on(TD::Types::Update::AuthorizationState) do |update|
#         @state = case update.authorization_state
#                 when TD::Types::AuthorizationState::WaitPhoneNumber
#                   :wait_phone_number
#                 when TD::Types::AuthorizationState::WaitCode
#                   :wait_code
#                 when TD::Types::AuthorizationState::WaitPassword
#                   :wait_password
#                 when TD::Types::AuthorizationState::Ready
#                   :ready
#                 else
#                   nil
#                 end
#       end
      
#     end

#     def client
#       return @client.connect.result[1]
#     end
# end


# # require 'tdlib-ruby'

# # TD.configure do |config|
# #   config.lib_path = '/usr/local/Cellar/tdlib/1.6.0/include/td/'

# #   config.client.api_id = 980209
# #   config.client.api_hash = '03062326232cb23c6770e7a735c2dae2'
# # end

# # TD::Api.set_log_verbosity_level(1)

# # client = TD::Client.new

# # begin
# #   state = nil

# #   client.on(TD::Types::Update::AuthorizationState) do |update|
# #     state = case update.authorization_state
# #             when TD::Types::AuthorizationState::WaitPhoneNumber
# #               :wait_phone_number
# #             when TD::Types::AuthorizationState::WaitCode
# #               :wait_code
# #             when TD::Types::AuthorizationState::WaitPassword
# #               :wait_password
# #             when TD::Types::AuthorizationState::Ready
# #               :ready
# #             else
# #               nil
# #             end
# #   end
  
# #   client.connect

# #   loop do
# #     case state
# #     when :wait_phone_number
# #       puts 'Please, enter your phone number:'
# #       phone = STDIN.gets.strip
# #       client.set_authentication_phone_number(phone, nil).wait
# #     when :wait_code
# #       puts 'Please, enter code from SMS:'
# #       code = STDIN.gets.strip
# #       client.check_authentication_code(code).wait
# #     when :wait_password
# #       puts 'Please, enter 2FA password:'
# #       password = STDIN.gets.strip
# #       client.check_authentication_password(password).wait
# #     when :ready
# #       client.get_me.then { |user| @me = user }.rescue { |err| puts "error: #{err}" }.wait
# #       break
# #     end
# #     sleep 0.1
# #   end

# # ensure
# #   # client.dispose
# # end



# # # c.search_public_chat("TechnicalPips").result[1].id
# # # c.get_chat_history(-1001287502434,0,0,10,true).result[1].messages[0].id