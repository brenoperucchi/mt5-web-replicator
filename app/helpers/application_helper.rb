module ApplicationHelper
	def show_svg(path)
	 return "/app/assets/images/#{path}"
	  # File.open("#{Rails.root}/app/assets/images/#{path}", "rb") do |file|
	  #   raw file.read
	  # end
	end	
end
