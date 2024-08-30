class API::V3::MetatraderPresenter < API::BasePresenter

  attr_accessor :params, :response, :request

  def initialize(params, request)
    @params = params
    @request = request
  end

  def execute
    if account.slave?
      slave_conciliate
    elsif account.copy?
      copy_conciliate
    end
  end



  

  # def pending_orders?
  #   account = Account.find_by(name: params[:account_id], kind: :slave, state: :enable)
  #   if account
  #     @response = account.slaves.opened.where.not(transaction_id: nil).where('closed_at >=? OR closed_at is NULL', (Time.zone.now - 31.days))
  #                      .collect { |t| t.api_request_attributes }.join('/')
  #   end
  #   !@response.nil?
  # end

end
