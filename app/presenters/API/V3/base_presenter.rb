module API
	module V3
		class BasePresenter

			attr_accessor :content, :json, :historyOrders, :positionOrders, :params

			def json
				@json = @message.content.present? ? JSON.parse(@message.content) : {}
			end

			def historyOrders
				json["HistoryOrders"] || []
			end

			def pendingOrders
				json["PendingOrders"] || []
			end

			def positionOrders
				json["PositionOrders"] || []
			end

			def conciliate_amount_history
				historyOrders.map{ |json| json["profit"].to_f }.sum
			end

			def conciliate_amount_position
				positionOrders.map{ |json| json["profit"].to_f }.sum
			end

			def conciliate_amount_pending
				pendingOrders.map{ |json| json["profit"].to_f }.sum
			end

			def params
				return {} unless @params.present?
				if(@params.is_a?(String))
					@params = parse_params(@params)
				elsif not @params.is_a?(Hash)
					JSON.parse(@params)
				end
			end

			def parse_params(params)
				begin
					# First attempt: try parsing as JSON directly
					return JSON.parse(params)
				rescue JSON::ParserError
					begin
						# Legacy rows stored Hash#inspect text. Never eval it (RCE): fall back
						# to a textual conversion and JSON.parse, which can only yield data.
						# Second attempt: regex conversion of Hash#inspect notation
						cleaned = params
							.gsub('=>', ':')
							.gsub(/(\w+):/, '"\1":')
							.gsub(/#<(File|Tempfile):[^>]+>/, '"file_object"')
						
						return JSON.parse(cleaned)
					rescue => e
						# Log error details and return empty hash if all attempts fail
						Rails.logger.error("Failed to parse params: #{e.message}")
						Rails.logger.error("Original params: #{params[0..100]}...")
						return {}
					end
				end
			end

		end
	end
end