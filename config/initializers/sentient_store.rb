module SentientStoreController
  def self.included(base)
    base.class_eval do
      helper_method :current_store
    end
  end

  def current_store
    Store.all.each do |store|
      store.url.split(';').each do |url| 
        @current_store = store if request.subdomain.split('.').first.try(:downcase) == url.downcase.strip
      end
    end
    @current_store
  end

end

module SentientStore
  
  def self.included(base)
    base.class_eval do

      def self.current
        Thread.current[:store]
      end

      def self.current=(o)
        raise(ArgumentError,
            "Expected an object of class '#{self}', got #{o.inspect}") unless (o.is_a?(self) || o.nil?)
        Thread.current[:store] = o
      end
  
      def make_current
        Thread.current[:store] = self
      end

      def current?
        !Thread.current[:store].nil? && self.id == Thread.current[:store].id
      end
    end
  end
end