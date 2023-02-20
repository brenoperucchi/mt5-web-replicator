class Numeric
  def to_sign
    if self > 0
      "+#{self}"
    elsif zero?
      "0"
    else
      "#{self}"
    end
  end
end

class Hash
  def to_o
    JSON.parse to_json, object_class: OpenStruct
  end
  
  def deep_find(key, object=self, found=nil)
    if object.respond_to?(:key?) && object.key?(key)
      return object[key]
    elsif object.is_a? Enumerable
      object.find { |*a| found = deep_find(key, a.last) }
      return found
    end
  end
end

class Integer
  def to_b?
    !self.zero?
  end
end

def round_to_5_minutes(t)
  t = (t + 3.minute)
  rounded = Time.at((t.to_time.to_i / 300.0).round * 300)
  t.is_a?(DateTime) ? rounded.to_datetime : rounded
end

class String
  def to_class
      my_const = Kernel.const_get(self)
      my_const.is_a?(Class) ? my_const : nil
  rescue NameError 
      nil
  end

  def is_a_defined_class?
      true if self.to_class
  rescue NameError
      false
  end

  def underscore
    self.gsub(/::/, '/').
    gsub(/([A-Z]+)([A-Z][a-z])/,'\1_\2').
    gsub(/([a-z\d])([A-Z])/,'\1_\2').
    tr("-", "_").
    downcase
  end

  def strip_emoji
    text = self
    text = text.force_encoding('utf-8').encode
    clean = ""

    # symbols & pics
    regex = /[\u{1f300}-\u{1f5ff}]/
    clean = text.gsub regex, ""

    # enclosed chars 
    regex = /[\u{2500}-\u{2BEF}]/ # I changed this to exclude chinese char
    clean = clean.gsub regex, ""

    # emoticons
    regex = /[\u{1f600}-\u{1f64f}]/
    clean = clean.gsub regex, ""

    #dingbats
    regex = /[\u{2702}-\u{27b0}]/
    clean = clean.gsub regex, ""
  end
  
  def to_underscore
    gsub(/([A-Z]+)([A-Z][a-z])/,'\1_\2').
    gsub(/([a-z\d])([A-Z])/,'\1_\2').
    tr('-', '_').
    gsub(/\s/, '_').
    gsub(/__+/, '_').
    downcase
  end
end