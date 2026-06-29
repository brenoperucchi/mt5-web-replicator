module TracesHelper
	def self.i18n_take_profit
		Trace::TAKE_PROFIT.map do |attr_name|
			I18n.t("helpers.label.trace.#{attr_name}", default: attr_name.to_s).titleize
		end
	end
end
