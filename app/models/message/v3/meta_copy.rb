class Message::V3::MetaCopy < Message::Message

  self.table_name = "messages"
  self.inheritance_column = :_type_disabled

  API_VERSION = "V3"

  state_machine :initial => :pending do
    before_transition :pending => :executed, :do => :execute_copy

    event :execute do
      transition :pending => :executed
    end

    event :restart do
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
      # copyPresenter.conciliate
    end
  end

  def presenter
    API::V3::CopyPresenter.new(params, self, account)
  end

end