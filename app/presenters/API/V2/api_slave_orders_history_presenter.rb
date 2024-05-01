class	API::V2::APISlaveOrdersHistoryPresenter
	attr_accessor :start_month, :end_month, :json

	def initialize(content)
		# content = content[:imentore_slave]
		@orders = []
		parse_message(content)
	end


	def parse_message(content)
		content = content.gsub("\u0000", "")
		@json = JSON.parse(content) if content.present? 
		@start_month = @json["start_month"] if @json["start_month"].present?
		@end_month   = @json["end_month"] if @json["end_month"].present?

		@orders = @json["orders_closed"] if @json["orders_closed"].present?
	end


	def orders
		@orders = @orders&.sort_by { |key, value| DateTime.parse(value["open_at"]) }
		@orders = @orders&.delete_if { |key, value| value["magic_number"].to_i == 0 || value["comment"].empty? }
	end

	def conciliate_amount
		profit = 0
		orders&.each_with_index do |(ticket, json), index|
			profit += json["profit"].to_f
		end
		profit
	end

end