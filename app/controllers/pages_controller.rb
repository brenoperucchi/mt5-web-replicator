class PagesController < ApplicationController
	layout 'stisla'

	def index
		@executed = Transaction.executed
		@traces = Store.first.traces.active
	end

end
