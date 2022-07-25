require "administrate/field/base"

class DisableBelongsTo <Administrate::Field::Base

  def to_s
    data
  end

  def default_value(obj, attr)
    case options[:type]
    when 'has_many'
      obj.send(options[:attribute]).try(options[:association]).map(&attr).join(', ')
    else
      # obj.send(options[:attribute]).try(attr)
      @data.send(attr)
    end
  end 

end