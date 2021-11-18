require 'json'
class MetaApi
	attr_accessor :ticket_id, :response, :account_id, :token, :position

	def initialize(meta_attributes = nil)
		@meta_attributes = meta_attributes
		@account_id = '4259f660-89e7-4f2d-9356-6502950feb71'
		@token = 'eyJhbGciOiJSUzUxMiIsInR5cCI6IkpXVCJ9.eyJfaWQiOiJlMTUwMjBkM2Y5Njg3NDM4OGUyOGEyMWFiYWZiNDY2MiIsInBlcm1pc3Npb25zIjpbXSwidG9rZW5JZCI6IjIwMjEwMjEzIiwiaWF0IjoxNjE4ODAxNDIxLCJyZWFsVXNlcklkIjoiZTE1MDIwZDNmOTY4NzQzODhlMjhhMjFhYmFmYjQ2NjIifQ.EuwKxunjBTHbg6HtjcKme-RdVTt0J6K5jimhJINzhhYGOLBnd_3WNgzzCutjB-8QHzdPt8PJlvUFj9q5lTRhTqrQ5P2da5UQRdzDV3f1ZReo5M3RWLccdcoLHu8Bzj25FcYqH2I8NLOfhK25VcFt-93a_VS1PWxGnEd2RwmYNllzUa1LgxMsyIdzfZwy2qj3OqnDhqvav3H_QqKYaOcRIYEbc-MbRWikMt70PbSZh0PMBeimgPKzcdRbDB7ggi8lIKntkbxbDkTADcM65ITqwkkpPulSH8MvIfFDtfeszSOOJNVEqILsPVFHokr4X3tdlzRCJyKs2VOepP3n6DbpwwLU2p4OmtfOgDndi1joS8QTplnb7WYzA89_yEz5EsK_abhc1FAPVSkXiVQUyyZhoasrHL8LX-N1JEbWEaLFVZsN6GamB_1Yul4DdH67OJP9d4sVvzX1PTzuXTLWDlDwUa9Wkncaq-ptjUm1dBOgUg3o-gSyNZ6KkjNWqdhDvHE6T_m0TzTQXiMQTLSoNoDTpSRrjUrBLjyEmAJYMbxiLgCo3CIppvDAUO5PkVsLwSmxNRVAahCoBV3Sf6aQP1s4j4wU_YzLJFvOrC8R5R8nnVKHZG02cs1CRPB4cOi0bK5TqOxOzRMdvEU86J0QpASfN2miQZ06-3gYJcfi4HjCl3I'
	end
	
	def body
		@body = { 
			actionType: @meta_attributes[:ordertype], 
			symbol: @meta_attributes[:instrument], 
			volume: @meta_attributes[:volume].to_f, 
			takeProfit: @meta_attributes[:takeprofit].to_f,
			stopLoss: @meta_attributes[:stoploss].to_f,
			comment: @meta_attributes[:comment],
			magic: @meta_attributes[:magicnumber],
		}

		ordertype = @meta_attributes[:ordertype]
		@body.merge!(openPrice: @meta_attributes[:openprice].to_f) if ordertype.include?("STOP") or ordertype.include?("LIMIT")
		return @body
	end

	def trade
		url = "https://mt-client-api-v1.agiliumtrade.agiliumtrade.ai"
		path = "/users/current/accounts/#{@account_id}/trade"
		resp = Faraday.post(url+path) do |req|
		  req.headers['Content-Type'] = 'application/json'
		  req.headers['auth-token'] = token
		  req.body = body.to_json
		end
		puts @response = JSON.parse(resp.body)
		unless @response['error'].present?
			positionId = response['positionId']
			path = "/users/current/accounts/#{@account_id}/positions/#{positionId}"
			resp = Faraday.get(url+path, nil, "auth-token" => token)
			@position = JSON.parse(resp.body)
		else
			false
		end
	end

	def modify(ticket, take_profit, stop_loss)
		url = "https://mt-client-api-v1.agiliumtrade.agiliumtrade.ai"
		path = "/users/current/accounts/#{@account_id}/trade"
		resp = Faraday.post(url+path) do |req|
		  req.headers['Content-Type'] = 'application/json'
		  req.headers['auth-token'] = token
		  req.body = {
		  	"actionType": "POSITION_MODIFY",
		  	"positionId": ticket,
		  	"takeProfit": take_profit.to_f,
		  	"stopLoss": stop_loss.to_f
		  }.to_json
		end
		puts @response = JSON.parse(resp.body)
		return @response['message'], @response['numericCode']
	end


	def close(ticket)
		url = "https://mt-client-api-v1.agiliumtrade.agiliumtrade.ai"
		path = "/users/current/accounts/#{@account_id}/trade"
		resp = Faraday.post(url+path) do |req|
		  req.headers['Content-Type'] = 'application/json'
		  req.headers['auth-token'] = token
		  req.body = {
			"actionType": "POSITION_CLOSE_ID",
		  	"positionId": ticket,
		  }.to_json
		end
		puts @response = JSON.parse(resp.body)
		return @response['message'], @response['numericCode']
	end

	def history_by_ticket(ticket)
		url = "https://mt-client-api-v1.agiliumtrade.agiliumtrade.ai"
		path = "/users/current/accounts/#{account_id}/history-deals/position/#{ticket}"
		# path = "/users/current/accounts/#{account_id}/history-orders/position/#{ticket}"
		# path = "/users/current/accounts/#{account_id}/history-orders/ticket/#{ticket}"
		# path = "/users/current/accounts/#{account_id}/history-deals/ticket/#{ticket}"
		# path = "/users/current/accounts/#{account_id}/positions/#{ticket}"
		# path = "/users/current/accounts/#{account_id}/positions/#{ticket}"
		# path = "/users/current/accounts/#{account_id}/orders/#{ticket}"
		# path = "/users/current/accounts/:accountId/positions/:positionId"

		resp = Faraday.get(url+path) do |req|
		  req.headers['auth-token'] = token
		end
		puts @response = JSON.parse(resp.body)
		return (@response.length >= 2)



	end

end