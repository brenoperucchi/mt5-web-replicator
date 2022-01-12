class PagesController < ApplicationController
	layout 'stisla'

	def index
		@executed = Store.first.transactions.executed
		@traces = Store.first.traces.active
	end

end
