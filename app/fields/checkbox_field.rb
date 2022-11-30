require "administrate/field/base"
class CheckboxField < Administrate::Field::Base
  def to_s
    data
  end

  def default_values
    resource.class.const_get :CONTROL_ROLE
  end

end