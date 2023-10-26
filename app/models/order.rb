class Order < ApplicationRecord
  # has_paper_trail
  attr_accessor :image_url, :profit_copy, :profit_slave

  belongs_to :trace
  belongs_to :store
  belongs_to :account
  belongs_to :message, class_name: 'Message::Message', foreign_key: :message_id, optional: true#, dependent: :destroy

  has_and_belongs_to_many :messages, class_name: 'Message::Message'

  has_many :slaves,       class_name: 'TransactionSlave', dependent: :destroy, foreign_key: :order_id

  has_many :loggings, as: :resourceable,  dependent: :destroy
  has_many :transactions,                 dependent: :destroy
  has_many :balances,                     dependent: :destroy, autosave: true
  has_many :accounts, through: :balances, source: :account,    autosave: true

  scope :image_to_process, ->{ joins(:image_attachment).where.not(image_attachment:nil).where(execute_at: nil).where(ready_at:nil).where.not(state: 'error') }
  scope :ready,     ->{ where(state: 'prepared').where.not(state:'error')}
  scope :error,     ->{ where(state: 'error')}
  scope :executed,  ->{ where(state: 'executed')}
  scope :closed,    ->{ where(state: 'closed')}
  scope :pending,   ->{ where(state: 'pending')}

  validates_uniqueness_of :content_id,  scope: [:account_id, :trace_id], on: :create, if: Proc.new { content_id != -1 }#, allow_blank: false, allow_nil: false#, if: Proc.new { account.try(:hedging?) }

  has_one_attached :image

  class << self
    def ransackable_scopes(_auth_object = nil)
      %i[profit_search ticket_search state_search]
    end
  end

  def self.ticket_search(value)
    self.where("CAST(content_id as TEXT) ILIKE ?", "%#{value}%")
  end

  def self.profit_search(value)
    self.joins(:transactions).where(transactions:{profit:0..value.to_f})
  end

  def self.state_search(*attrs)
    attrs.reject!{|item| item.empty?}
    return true unless attrs.present?
    self.where(state:attrs)
    
  end


  state_machine :initial => :pending do
    after_transition :executed => :closed, :do => :update_state

    event :prepare do
      # transition :pending => :prepared, :if => lambda { |order| order.restrict_symbol? }
    end
    event :execute do
      transition [:pending, :prepared] => :executed
    end
    event :erro do
      transition [:pending, :prepared, :executed] => :error
    end
    event :close do
      transition [:executed] => :closed
    end
    event :cancel do
      transition [:prepared, :executed, :error] => :pending
    end

    state :closed do
      def update_state(state)
        return (slaves.closed_deleted.count == slaves.count and transactions.first.closed?)
      end
    end

    state :prepared do
      def update_state(state)
        self.update_column(:ready_at, Time.current)
        system("rm -rf #{Rails.root}/public/output.jpg") 
      end
    end
    state :executed do
      def update_state(state)
        self.update_column(:execute_at, Time.current)
      end
      def close_state?(state)
        trans_count = self.transactions.count
        closed_count = self.transactions.closed.count
        trans_count == closed_count ? self.update_column(:execute_at, Time.current) : false
      end
    end
    state :pending do
      def update_state(state)
        self.update_column(:execute_at, nil)
        self.update_column(:ready_at, nil)
      end
    end
  end


  def message_action(action, value=0)
    case action
    when "open_order"
      create_transactions!
    when "close_order"
      transactions.map(&:close_order)
    when "set_break_even"
       transactions.executed.reverse.each{|t| t.set_all_sl_and_tp_order(nil, value)}
    when "set_stop_loss"
      transactions.executed.reverse.each{|t| t.set_all_sl_and_tp_order(nil, value)}
    when "set_take_profit"
      transactions.executed.reverse.each{|t| t.set_all_sl_and_tp_order(value, nil)}
    else
      false
    end
  end

  def create_transactions!
    limit = self.trace.take_profit_limit.to_i
    takeprofits = message.serializer.takeprofits.count
    for_limit = limit <= takeprofits ? limit : takeprofits
    self.trace.accounts.slave.each do |account|
      transaction = account.transactions.create(message.serializer.transaction_attributes)
      if transaction and not transaction.error?
        for i in (0..for_limit-1) do 
          if trace.copy?
            api_attributes = SerializerAPITransaction.new(transaction.message.content).api_attributes
          else
            api_attributes = message.serializer.transaction_attributes(i).except(:message_id, :order_id).merge(lot: account.instrument_volume(transaction.symbol, i))
          end

          slave = transaction.slaves.create(api_attributes.merge(symbol: transaction.symbol, state:'pending', ticket:nil, price_request:transaction.price_request, profit:nil, account:account))
        end
      end
      transaction.execute
    end
  end

  # def restrict_symbol?
  #   if self.trace.store.tag_list.map(&:downcase).include?(symbol.downcase)
  #     self.message_response = "Restrict Store Symbol"
  #     self.erro
  #     return false
  #   else
  #     return true
  #   end
  # end

  def restrict_magic_number(resource)
    unless resource.account.magics_accept.blank?
      trace_magic_number = self.try(:trace).try(:name_id)
      magic_numbers = Order.magic_numbers_split(resource.account.magics_accept)
      changeset = resource.try(:versions).try(:last).try(:changeset)
      version = resource.try(:version)
      unless magic_numbers.detect{|x| x == resource.magic_number}
        resource.loggings.create(content:"#{resource.class.name} ##{resource.id} has magic number #{resource.magic_number} and the account: #{resource.try(:account).try(:name)} only accepted: #{magic_numbers.join(" - ")}", changeset: changeset, version:version, state: 'ERROR', parent:message)
        resource.erro!
      end
    end
    resource.error?
  end  

  def api_request_attributes(resource)
    # magicnumber = resource.try(:trace).try(:name_id)
    ticket_master = resource.try(:ticket) || resource.try(:ticket_master)
    ticket_slave = resource.try(:ticket_slave) || 0
    master_id  = resource.try(:master).try(:id) || 0
    deal_ticket = resource.try(:ticket_deal).blank? ? 0 : resource.ticket_deal
    seconds_ago = resource.try(:seconds_ago) || 0
    openprice = price_open(resource)
    order_trace = self.trace_id
    openat = Rails.env.test? ? 0 : resource.open_at.to_i
    comment = resource.try(:comment).to_s.gsub(/[^0-9A-Za-z]/, '_')
    contract_volume = resource.try(:account).try(:contract_volume)
    "#{resource.ordertype}|#{ticket_master}|#{ticket_slave}|#{order_trace}|#{resource.id}|#{resource.magic_number}|#{master_id}|#{openprice}|#{resource.lot}|#{resource.stop_loss}|#{resource.take_profit}|#{resource.state}|#{resource.symbol}|#{deal_ticket}|#{seconds_ago}|#{comment}|#{openat}|#{contract_volume}"
  end

  def price_open(resource)
    if resource.pending?
      (resource.ordertype == "0" or resource.ordertype == 1) ? "0" : resource.price_request
    else
      resource.price_open
    end
  end

  def order_pending?
    self.content.upcase.include?('STOP') or self.content.upcase.include?('LIMIT')
  end

  def ocr_text(url:nil, file:nil)
    if file
      path = Rails.root
      image_path = "#{path}/public/output.jpg"
      # image_path = ActiveStorage::Blob.service.path_for(self.image.key)
      system("#{path}/lib/textcleaner -c '0,140,0,0' -g -t 30 -s 2 -u -p 5 -T #{image_path} #{image_path}")
      image = RTesseract.new(image_path)
      return image.to_s.gsub(/[^A-Za-z]+/, "") #.to_s.scan(/([A-Z]{1,3} *\/ *[A-Z]{1,3})/)

    elsif url
      # path = rails_blob_path(self.image, disposition: "attachment", only_path: true)
      # resource = OcrSpace::Resource.new(apikey: "14ce99dd8788957")
      # result = resource.convert url: "http://benincasouza.tplinkdns.com:8080/#{path}"
    end
  end


  def self.magic_numbers_split(magic_numbers)
    delimiters = [',', ' ', "'",'-','_','.','/', ":", ";"]
    magic_numbers = magic_numbers.try(:split, (Regexp.union(delimiters))).try(:flatten)
    magic_numbers.reject! { |item| item.blank? } if magic_numbers
    (magic_numbers.blank? or magic_numbers.nil?) ? nil : magic_numbers
  end

  def calcule_lot(value)
    decimal = 10 ** (value.to_s.split('.').last.size)
    (self.trace.lots.to_f * value * decimal).round / decimal.to_f
  end


  def profit_copy
    profits = transactions.to_a
    return 0 if profits.blank?
    profits.sum(&:profit) / profits.count
  end

  def profit_slave
    profits = slaves.closed.to_a
    return 0 if profits.blank?
    profits.sum(&:profit) / profits.count
  end

  def ordertype
    case transactions.try(:first).try(:ordertype)
    when "0"
      "BUY"
    when '1'
      'SELL'
    when '2'
      'BUY LIMIT'
    when '3'
      'BUY STOP'
    when '4'
      'SELL LIMIT'
    when '5'
      'SELL STOP'
    end
  end

end