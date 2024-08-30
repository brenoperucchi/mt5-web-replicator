class Message::V3::MetaSlave < Message::Message
  
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
      slavePresenter = API::V3::SlavePresenter.new(params, request, self, account)
      slavePresenter.execute_status
      slavePresenter.conciliate
      slavePresenter.slaves
      self.response = slavePresenter.response
    end
  end

end