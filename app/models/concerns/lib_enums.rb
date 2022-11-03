module LibEnums
  extend ActiveSupport::Concern

  included do
		validate do
	    self.class::ENUMS.each do |e|
	      if instance_variable_get("@not_valid_#{e}")
	        errors.add(e.to_sym, "must be #{self.class.send("#{e}s").keys.join(' or ')}")
	      end
	    end
	  end

		self::ENUMS.each do |e| 
		  self.define_method("#{e}=") do |value|
		    if !self.class.send("#{e}s").keys.include?(value)
		      instance_variable_set("@not_valid_#{e}", true)
		    else
		      super value
		    end
		  end
		end
	end
end