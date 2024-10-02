class Message::V3::MetaSlave < Message::Message
  
  attr_accessor :request

  self.table_name = "messages"
  self.inheritance_column = :_type_disabled

  API_VERSION = "V3"

  state_machine :initial => :pending do
    before_transition :pending => :executed, :do => :execute_slave
    # before_transition [:pending, :executed] => :conciliated, :do => :execute_conciliated
    
    event :execute do
        transition :pending => :executed
    end
    event :conciliate do
      transition [:pending, :executed] => :conciliated
    end    
    event :erro do
      transition [:pending, :executed] => :error
    end    
  end

  validates_presence_of :account


  def execute_slave
    if self.valid?
      slavePresenter = presenter
      slavePresenter.execute_status
      slavePresenter.slaves
      self.response = slavePresenter.response
    end
  end  

  def execute_conciliated
    if self.valid?
      slavePresenter = presenter
      slavePresenter.slaves
      # slavePresenter.conciliate
      self.response = slavePresenter.response
    end
  end


  def presenter
    API::V3::SlavePresenter.new(params, self, account)
  end

end