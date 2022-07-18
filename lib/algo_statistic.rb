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
	  begin
	    (profit/loss*pay_off)    
	  rescue
	    0
	  end
	end

	def self.drawdown(transactions)
	  drawdown_balance = 0
	  drawdown_max = 0

	  transactions.order(created_at: :desc).each do |association|
	    value = association.profit.to_f
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