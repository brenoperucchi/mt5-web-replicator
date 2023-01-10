require "administrate/field/base"
class CheckboxField < Administrate::Field::Base
  def to_s
    data
  end

  def default_values
    if options[:collection_key].is_a?(Array) 
      options[:collection_key]
    else resource.class.const_defined?(options[:collection_key])
      resource.class.const_get options[:collection_key]
    end
  end

end