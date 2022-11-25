require "administrate/field/base"

class DisableAssociation <Administrate::Field::Base

  def to_s
    data
  end

  def default_value(obj, attr)
    case options[:type]
    when 'has_many' 
      if options[:scope].nil?
        obj.send(options[:association]).map(&attr).join(', ')
      elsif options[:scope].present?
        obj.send(options[:scope]).try(options[:association]).map(&attr).join(', ')
      end
    else
      obj.send(options[:attribute]).try(attr)
    end
  end 

end