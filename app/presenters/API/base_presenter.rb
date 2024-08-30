module API
	class BasePresenter

		attr_accessor :content, :json, :historyOrders, :positionOrders, :params

		# def content
		# 	content = File.open(params["data"]["tempfile"]).try(:read)
		# 	@content = content.gsub!("\u0000", "")
		# end


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
			JSON.parse(@params)
		end
	end
end
