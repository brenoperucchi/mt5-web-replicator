module LibEnums
  extend ActiveSupport::Concern

  included do
    validate :validate_enum_values

    self.defined_enums.keys.each do |enum|
      define_method("#{enum}=") do |value|
        value_inclusion = self.class.send("#{enum.pluralize}").keys
        if value.nil? || !value_inclusion.include?(value)
          instance_variable_set("@not_valid_#{enum}", true)
        else
          super(value)
        end
      end
    end
  end

  private

  def validate_enum_values
    self.class.defined_enums.keys.each do |enum|
      if instance_variable_get("@not_valid_#{enum}")
        errors.add(enum, "must be one of #{enum_values(enum).join(' or ')}")
      end
    end
  end

  def enum_values(enum)
    self.class.send("#{enum.pluralize}").keys
  end
end
