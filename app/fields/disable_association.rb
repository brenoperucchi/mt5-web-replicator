require "administrate/field/base"

class DisableAssociation <Administrate::Field::Base

  def to_s
    data
  end

  def html_class
    hide_class = options[:type] == 'hide'? ' field-hide' : ""
    self.class.html_class + hide_class
  end


  def default_value(obj, attr)
    case options[:type]
    when 'has_many' 
      if options[:association].present?
        resource.send(options[:association]).map(&attr).join(', ')
      elsif options[:scope].present?
        resource.send(options[:scope]).try(options[:association]).map(&attr).join(', ')
      end
    else
      if options.key?(:attribute)
        resource.send(options[:attribute]).try(attr)
      else
        resource.send(attribute).try(attr)
      end
    end
  end 

end