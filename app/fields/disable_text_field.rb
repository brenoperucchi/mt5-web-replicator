require "administrate/field/base"

class DisableTextField < Administrate::Field::Base

  def to_s
    data
  end

  def default_value(obj)
    options[:value] || obj.send(attribute)
  end

end
