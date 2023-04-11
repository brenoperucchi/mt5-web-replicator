module AlgoStatistic

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
		(result.is_a?(Float) or result.nan?) ? 0 : result
	end

	def self.profit_drawdown(profit, drawdown)
		return 0 if drawdown == 0
		result = profit/drawdown.to_f
		(result.is_a?(Float) or result.nan?) ? 0 : result
	end

	def self.expect_pay_off(profit_trades, total_trades, gross_profit, loss_trades, gross_loss)
		result = (profit_trades/total_trades) * (gross_profit / profit_trades) - (loss_trades / total_trades) * (gross_loss / loss_trades)
		(result.is_a?(Float) or result.nan?) ? 0 : result
	end

	def self.drawdown(collection)
	  drawdown_balance = 0
	  drawdown_max = 0

	  collection.each do |record|
	    value = record.profit.to_f
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
	
end