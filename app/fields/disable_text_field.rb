require "administrate/field/base"

class DisableTextField < Administrate::Field::Base

  def to_s
    data
  end

  def default_value(obj=nil)
    resource.send(attribute)
  end

  def html_class
    hide_class = options[:type] == 'hide'? ' field-hide' : ""
    self.class.html_class + hide_class
  end

end
