module AlgoStatistic
	extend ActiveSupport::Concern

	included do

		def dates_dashboard(collection)
			(collection.first.closed_at.beginning_of_day.to_datetime..collection.last.closed_at.end_of_day.to_datetime)
		end

		def dashboard_capital_accumulated(heading = false)
		  amount_total = 0
		  collection = masters_scope(:masters, :closed).order(closed_at: :asc).where.not("transactions.closed_at is NULL AND transactions.profit = 0.0")
		  collection_array = []
		  if collection.present?
		    collection_array = [{day:(collection.first.closed_at - 1.day).strftime("%Y-%m-%d"), portfolio: 0, profit: 0, loss:0}] if heading
		    dates_dashboard(collection).each do |date|
		      profit = collection.where(closed_at: date.beginning_of_day..date.end_of_day).sum(&:profit)
		      amount_total = profit + amount_total
		      profit_value = profit <= 0 ? 0 : profit
		      loss_value = profit >= 0 ? 0 : profit
		      if profit_value != 0 or loss_value != 0
		        collection_array.push({day:date.strftime("%Y-%m-%d"), portfolio: number_with_precision(amount_total.to_f, precision:2), profit: number_with_precision(profit_value, precision:2), loss: number_with_precision(loss_value, precision:2)})
		      end
		    end
		  end
		  collection_array
		end

		def dashboard_drawdown
		  amount_total = 0
		  collection = masters_scope(:masters, :closed).order(closed_at: :asc)
		  collection_array = []
		  if collection.present?
		    collection_array = [{day:(collection.first.closed_at - 1.day).strftime("%Y-%m-%d"), drawdown: 0}]
		    dates_dashboard(collection).each do |date|
		      records = collection.where(closed_at: date.beginning_of_day..date.end_of_day)
		      drawdown = AlgoStatistic.drawdown(records)
		      collection_array.push({day:date.strftime("%Y-%m-%d"), drawdown: drawdown})
		    end
		  end
		  collection_array
		end

		def dashboard_monthy_amount
		  amount_total = 0
		  date    = ['date']
		  capital = ['capital']
		  profit  = ['profit']
		  array = []
		  self.transactions.closed.where.not(closed_at:nil).order('closed_at asc').group_by{|x| x.closed_at.beginning_of_month.strftime("%b/%Y")}.map do |k,v|
		    amount_total = v.sum(&:profit) + amount_total
		    {date:k, capital: amount_total, profit: v.sum(&:profit)} 
		  end
		end
	end


	def self.profit_trade(trades, gain_trades)
	  result = (gain_trades/trades)
	  result = (result * 100).round(2)
	  result.nan? ? 0 : result
	end

	def self.loss_trade(trades, loss_trades)
	  result = (loss_trades/trades)
	  result = (result * 100).round(2)
	  result.nan? ? 0 : result
	end

	def self.pay_off(gain, gain_operation, loss, loss_operation)
	  result = (gain/gain_operation)/(loss/loss_operation)
	  result.nan? ? 0 : result
	end

	def self.profit_factor(profit, loss, pay_off)
		# divide = loss
		return 0 if loss == 0
		result = profit/loss.to_f
		(result.is_a?(Float) and result.nan?) ? 0 : result
	end

	def self.profit_drawdown(profit, drawdown)
		return 0 if drawdown == 0
		result = profit/drawdown.to_f
		(result.is_a?(Float) and result.nan?) ? 0 : result
	end

	def self.expect_pay_off(profit_trades, total_trades, gross_profit, loss_trades, gross_loss)
		result = (profit_trades/total_trades) * (gross_profit / profit_trades) - (loss_trades / total_trades) * (gross_loss / loss_trades)
		(result.is_a?(Float) and result.nan?) ? 0 : result
	end

	def self.drawdown(collection)
	  drawdown_balance = 0
	  drawdown_max = 0


	  # collection.each do |record|
	  #   value = record.profit.to_f
	  collection.group_by{|x| x.created_at.strftime("%Y %m %d")}.each do |date, record|
	    value = record.sum(&:profit)
	    if value < 0 
	      drawdown_balance = drawdown_balance + value
	      
	      if drawdown_balance < drawdown_max
	        drawdown_max = drawdown_balance
	      end

	    else
	      drawdown_balance = drawdown_balance + value
	      if drawdown_balance > 0
	        drawdown_balance = 0 
	      end
	    end
	  end
	  drawdown_max
	end

	# def self.drawdown_days(collection)
	#   drawdown_balance = 0
	#   drawdown_max = 0
	#   drawdown_days = 0

	#   # collection.each do |record|
	#   #   value = record.profit.to_f
	#   collection.group_by{|x| x.created_at.strftime("%Y %m %d")}.each do |date, record|
	#     value = record.sum(&:profit)
	#     if value < 0 
	#       drawdown_balance = drawdown_balance + value
	      
	#       if drawdown_balance < drawdown_max
	#       	drawdown_days += 1
	#         drawdown_max = drawdown_balance
	#       end

	#     else
	#       drawdown_balance = drawdown_balance + value
	#       if drawdown_balance > 0
	#         drawdown_balance = 0 
	#       end
	#     end
	#   end
	#   drawdown_days
	# end


	def self.drawdown_dates(collection)
	  drawdown_balance = 0
	  drawdown_max = 0
	  drawdown_dates = []
	  drawdown_dates_max = []


	  collection.group_by{|x| x.created_at.strftime("%Y %m %d")}.each do |date, record|
	    value = record.sum(&:profit)
	    if value < 0 
	      drawdown_balance = drawdown_balance + value
      	drawdown_dates.push(Date.strptime(date,"%Y  %m %d"))
	      if drawdown_balance < drawdown_max
	      	drawdown_dates_max = (drawdown_dates)
	        drawdown_max = drawdown_balance
	      end
  		else
	      drawdown_balance = drawdown_balance + value
	      if drawdown_balance > drawdown_max
	        drawdown_balance = 0 
	      	drawdown_dates = []
	      end
	    end
	  end
	  return drawdown_dates_max
	end

	# def self.drawdown_dates(collection)
	#   drawdown_balance = 0
	#   drawdown_max = 0
	#   drawdown_dates = []
	#   drawdown_dates_max = []

	#   # collection.reverse.each do |record|
	#   collection.group_by{|x| x.created_at.strftime("%Y %m %d")}.each do |date, record|
	#     # value = record.profit.to_f
	#     value = record.sum(&:profit)
	#     # puts "----------BEGIN-------------"
	#     # # puts "Date => #{record.created_at.strftime("%Y/%m/%d")}"
	#     # puts "Date => #{date}"
	#     # puts "Value => #{value.to_f}"
	#     # puts "drawdown_balance => #{drawdown_balance.to_f}"
	#     if value < 0 
	#       # puts "drawdown_balance + value => #{drawdown_balance.to_f} + #{value} = #{drawdown_balance + value}"
	#       drawdown_balance = drawdown_balance + value
	#       # puts "drawdown_max => #{drawdown_max.to_f}"
	#       # puts "if drawdown_balance < drawdown_max => #{drawdown_balance} < #{drawdown_max} = #{drawdown_balance < drawdown_max}"
  #     	# # drawdown_dates.push([record.created_at.strftime("%Y/%m/%d"), value])
  #     	drawdown_dates.push(Date.strptime(date,"%Y  %m %d"))
  #     	# puts "drawdown_dates => #{drawdown_dates}"
	#       if drawdown_balance < drawdown_max
	#       	drawdown_dates_max = (drawdown_dates)
  #     		# puts "drawdown_dates_max => #{drawdown_dates}"
	#         drawdown_max = drawdown_balance
	#         # puts "drawdown_max = drawdown_balance => #{drawdown_max.to_f}"
	#       end
  # 		else
	#     	# puts "ELSE"
	#       # puts "drawdown_balance + value => #{drawdown_balance.to_f} + #{value} = #{drawdown_balance + value}"
	#       drawdown_balance = drawdown_balance + value
	#       # puts "if drawdown_balance > drawdown_max => #{drawdown_balance} > #{drawdown_max} = #{drawdown_balance > drawdown_max}"
	#       if drawdown_balance > drawdown_max
	#         drawdown_balance = 0 
	#       	# puts "Value >= 0 ELSE - drawdown_dates => #{drawdown_dates}"
	#       	drawdown_dates = []
	#       	# puts "Value >= 0 ELSE - drawdown_dates => #{drawdown_dates}"
	#         # puts "drawdown_balance = 0  => #{drawdown_balance.to_f}"
	#         # puts "drawdown_max 		 = 0  => #{drawdown_max.to_f}"
	#       end
	#     end
	#     # puts "----------END-------------"
	#   end
	#   # "#{drawdown_dates.first.strftime("%Y/%m/%d")} - #{drawdown_dates.last.strftime("%Y/%m/%d")}"
	#   # puts "drawdown_dates => #{drawdown_dates}"
	#   return drawdown_dates_max
	# end

	# def self.drawdown_dates(collection)
	#   drawdown_balance = 0
	#   drawdown_max = 0
	#   drawdown_dates = []

	#   collection.group_by{|x| x.created_at.strftime("%Y %m %d")}.each do |date, record|
	#     value = record.sum(&:profit)
  #     drawdown_balance = drawdown_balance + value
	#     if value < 0 
	      
	#       if drawdown_balance < drawdown_max
	#       	drawdown_dates.push("#{date} - #{value}")
	#       	drawdown_dates.push(date)
	#         drawdown_max = drawdown_balance
	#       end

	#     else
	#       # drawdown_balance = drawdown_balance + value
	#       if drawdown_balance > drawdown_max
	#         drawdown_balance = drawdown_max
	#         # drawdown_max = 0
	#       end
	#     end
	#   end
	#   drawdown_dates
	#   # return [] unless drawdown_dates.present?
	#   # "#{Date.strptime(drawdown_dates.first,"%Y  %m %d").strftime("%Y/%m/%d")} - #{Date.strptime(drawdown_dates.first,"%Y  %m %d").strftime("%Y/%m/%d")}"
	# end
	
end