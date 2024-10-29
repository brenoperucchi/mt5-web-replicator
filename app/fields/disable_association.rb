require "administrate/field/base"

class DisableAssociation <Administrate::Field::Base

  def self.permitted_attribute(attr, _options = {})
    # This may seem arbitrary, and improvable by using reflection.
    # Worry not: here we do exactly what Rails does. Regardless of the name
    # of the foreign key, has_many associations use the suffix `_ids`
    # for this.
    #
    # Eg: if the associated table and primary key are `countries.code`,
    # you may expect `country_codes` as attribute here, but it will
    # be `country_ids` instead.
    #
    # See https://github.com/rails/rails/blob/b30a23f53b52e59d31358f7b80385ee5c2ba3afe/activerecord/lib/active_record/associations/builder/collection_association.rb#L48
    if _options[:type] == 'has_many'
      { "#{attr.to_s.singularize}_ids".to_sym => [] }
    else
      super
    end
  end

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