require "administrate/field/base"

class DisableTextField < Administrate::Field::Base

  def to_s
    data
  end

  def default_value(obj=nil)
    resource.send(attribute)
  end

end
