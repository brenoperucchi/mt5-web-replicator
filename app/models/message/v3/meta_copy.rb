class Message::V3::MetaCopy < Message::Message

  self.table_name = "messages"
  self.inheritance_column = :_type_disabled

  API_VERSION = "V3"

  state_machine :initial => :pending do
    before_transition :pending => :executed, :do => :execute_copy

    event :execute do
      transition :pending => :executed
    end

    event :reset do
      transition :executed => :pending
    end

    event :erro do
      transition [:pending, :executed] => :error
    end    
  end

  validates_presence_of :account


  def execute_copy
    if self.valid?
      copyPresenter = presenter
      copyPresenter.opening
      copyPresenter.closing 
      copyPresenter.pending
      copyConciliatePresenter = API::V3::CopyConciliatePresenter.new(params, self, account)
      copyConciliatePresenter.conciliate
    end
  end

  def execute_conciliated
    presenter = API::V3::CopyConciliatePresenter.new(params, self, account)
    presenter.conciliate
  end
  

  def presenter
    API::V3::CopyPresenter.new(params, self, account)
  end

end