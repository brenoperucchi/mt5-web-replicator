module Telegram::Util
	extend ActiveSupport::Concern

		def telegram_message_prepare(state)
			attributes = {"take_profit" => self.take_profit, "stop_loss" => self.stop_loss, "lot" => self.lot}.merge(self.changes)

			attributes = better_array(attributes)

			string = "--------------------\r\n"
			string << "Time: #{I18n.localize DateTime.now, format: :short2}\r\n"
			string << "SYMBOL: #{symbol}\r\n"
			string << "STATE: #{state}\r\n"
			string << "COMMENT ID: #{self.ticket}\r\n"
			string << "\r\n"
			if state == :OPEN
				string << "PRICE OPEN: #{self.price_open}\r\n"
			elsif state == :CLOSED
				string << "PRICE CLOSED: #{self.price_closed}\r\n"
				string << "PROFIT: #{self.profit}\r\n"
			# elsif state == :MODIFY
			# 	string << "Modify: #{self.changes}\r\n"
			end
			string << "TAKE PROFIT: #{attributes["take_profit"]}\r\n"
			string << "STOP LOSS: #{attributes["stop_loss"]}\r\n"
			string << "VOLUME: #{attributes["lot"]}\r\n"
			string << "--------------------"

			return string
			
		end

		private 
		
		def better_array(attributes)
			attributes.each do |key, value|
			 attributes[key] = value.is_a?(Array) ? "#{value[0]} => #{value[1]}" : value 
			end
		end
	
	
end