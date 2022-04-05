require "administrate/field/base"

class DisableBelongsTo <Administrate::Field::Base

  def to_s
    data
  end

  def default_value(obj, attr)
    obj.send(options[:attribute]).try(attr)
  end 

end