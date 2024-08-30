class Message::V3::MetaCopy < Message::Message

  attr_accessor :request

  self.table_name = "messages"
  self.inheritance_column = :_type_disabled

  API_VERSION = "V3"

  state_machine :initial => :pending do
    before_transition :pending => :executed, :do => :execute_copy

    event :execute do
        transition :pending => :executed
    end
    event :erro do
      transition [:pending, :executed] => :error
    end    
  end

  validates_presence_of :account


  def execute_copy
    if self.valid?
      copyPresenter = API::V3::CopyPresenter.new(params, request, self, account)
      copyPresenter.opening
      copyPresenter.pending
      copyPresenter.closing 
      copyPresenter.conciliate
    end
  end

end