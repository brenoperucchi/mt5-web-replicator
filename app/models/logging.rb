class Logging < ApplicationRecord

  has_ancestry

  store :settings, accessors:[:error_message, :error_backtrace, :request_url]

  has_many :orders
  has_many :transactions, through: :orders, source: :transactions
  has_many :files, as: :uploadable, class_name: "UploadFile"#, dependent: :destroy

  belongs_to :user, optional: true
  belongs_to :account,  optional: true

  belongs_to :loggerable, polymorphic: true, optional:true
  belongs_to :resourceable, polymorphic: true, optional:true
  belongs_to :version, :class_name => "PaperTrail::Version", :foreign_key => "version_id", optional: true

  def detect_closed?
    YAML.load(content)["action"] == "CLOSED" if loggerable.class.name == "TransactionSlave"
  end


  def file_content
    files.first.file.download if files.present? and state == "LOGFILE"
  end

end

# def conciliate_metatrader(params)
#   if params.dig(:logfile).present?
#     content   = File.open(params[:logfile][:tempfile]).try(:read)
#     presenter = API::V2::APISlaveOrdersHistoryPresenter.new(content)
#     count =0 
#     if presenter.orders.present?
#       presenter.orders.each do |json|
#         count += 1
#         slave = TransactionSlave.find_by(symbol: json["symbol"], ticket_slave: json["ticketSlave"], account: account)
#         if slave
#           slave.profit = json["profit"] if slave.profit != json["profit"].to_f
#           if slave.state == "closed"
#             slave.save
#           else state != "closed"
#             slave.remove
#           end
#         else
#           order = Order.find_by(symbol: json["symbol"], content_id: json["ticketMaster"])
#           ticketMaster = json["ticketMaster"] == 0 ? -1 : json["ticketMaster"]
#           if order
#             trace = order.trace
#             comment = json["ticketMaster"]
#           else
#             comment = "manual_order"
#             trace = Trace.create_with(name: "manual_orders", name_id: -1, store: account.store, kind: 2, contract_volume_max: 1, customer_plans: [account.store.customer_plans.first]).find_or_create_by(name: "manual_orders", name_id: -1)
#             order = Order.create(symbol: json["symbol"], content: json, content_id: ticketMaster, account: account, state: 'manual', store: account.store, trace: trace)
#           end
#           slave = order.slaves.create(ticket_master: ticketMaster, ticket_slave: json["ticketSlave"], symbol: json["symbol"], comment: comment, open_at: json["openAt"], closed_at: json["closeAt"], profit: json["profit"], state: "closed", account: account, trace: trace)
#         end
#         if slave.valid?
#           self.update(content: presenter.strip_content, loggerable:loggerable, resourceable:self, changeset: slave.versions.try(:last).try(:changeset), version: slave.versions.try(:last), parent: slave.loggings.try(:first)) 
#         end
#       end
#     end
#   end    
# end
