module Balance::Base

	def balance_today
		date = Time.zone.now
		self.slaves.where(created_at: date.beginning_of_day..date.end_of_day).sum(&:profit)
	end

	def balance_week
		date = Time.zone.now
		self.slaves.where(created_at: date.beginning_of_week..date.end_of_week).sum(&:profit)
	end

	def balance_month
		date = Time.zone.now
		self.slaves.closed.where(created_at: date.beginning_of_month..date.end_of_month).sum(&:profit)
	end

	def balance_7days
		date = Time.zone.now
		self.slaves.where(created_at: (date - 7.days)..date).sum(&:profit)
	end

	def balance_month_count
		date = Time.zone.now
		self.slaves.closed.where(created_at: date.beginning_of_month..date.end_of_month).count
	end

end