load "#{Rails.root}/lib/telegram/signal.rb"
class Order < ApplicationRecord
  has_paper_trail
  
  attr_accessor :image_url, :new_value

  # enum state: %i[ pending prepared ordered error ]
  belongs_to :trace
  belongs_to :message
  has_many :transactions, :class_name => "Transaction", :foreign_key => "order_id", dependent: :destroy

  scope :image_to_process, ->{ joins(:image_attachment).where.not(image_attachment:nil).where(execute_at: nil).where(ready_at:nil).where.not(state: 'error') }

  scope :ready, ->{ where(state: 'prepared').where.not(state:'error') }

  scope :error, ->{ where(state: 'error')}

  has_one_attached :image

  state_machine :initial => :pending do
    after_transition :pending => :prepared, :do => :update_state
    after_transition :prepared => :executed, :do => :update_state
    before_transition :executed => :closed, :do => :close_state?
    after_transition [:prepared, :executed] => :pending, :do => :update_state

    event :prepare do
      transition :pending => :prepared, :if => lambda { |order| order.restrict_symbol? }
    end
    event :execute do
      transition :prepared => :executed
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

    state :prepared do
      def update_state(state)
        self.update_column(:ready_at, DateTime.now)
        system("rm -rf #{Rails.root}/public/output.jpg") 
      end
    end
    state :executed do
      def update_state(state)
        self.update_column(:execute_at, DateTime.now)
      end
      def close_state?(state)
        trans_count = self.transactions.count
        closed_count = self.transactions.closed.count
        trans_count == closed_count ? self.update_column(:execute_at, DateTime.now) : false
      end
    end
    state :pending do
      def update_state(state)
        self.update_column(:execute_at, nil)
        self.update_column(:ready_at, nil)
      end
    end
  end


  def message_action(action)
    case action
    when "open_order"
      create_order!
    when "close_order"
      transactions.map(&:close_order)
    when "set_break_even"
       # transactions.map(&:set_stop_loss_order)
    when "set_stop_loss"
      transactions.reverse.each{|t| t.set_stop_loss_order(new_value)}
    when "set_take_profit"
    
    else
      false
    end
  end

  def create_order!
    message.trace.volumes.each_with_index do |volume, index|
      response = meta_order_send(trace, message.serializer.meta_attributes(index))
      transaction = self.transactions.create(message.serializer.transaction_attributes(response))
      # message.execute if transaction

      response[:response] == "OK" ? transaction.execute : transaction.erro
    end

  end

  def restrict_symbol?
    if self.trace.store.tag_list.map(&:downcase).include?(symbol.downcase)
      self.message_response = "Restrict Store Symbol"
      self.erro
      return false
    else
      return true
    end
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

  def calcule_lot(value)
    decimal = 10 ** (value.to_s.split('.').last.size)
    (self.trace.lots.to_f * value * decimal).round / decimal.to_f
  end



end
