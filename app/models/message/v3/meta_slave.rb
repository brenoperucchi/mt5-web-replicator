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
    event :reset do
      transition [:pending, :executed, :conciliated] => :pending
    end    
  end

  validates_presence_of :account


  def execute_slave
    if self.valid?
      presenter.execute_status
    end
  end  
  
  def execute_conciliated
    presenter = API::V3::SlaveConciliatePresenter.new(params, self, account)
    presenter.conciliate
  end
  
  def presenter
    API::V3::SlavePresenter.new(params, self, account)
  end

  def response
    presenter.slaves
  end

end